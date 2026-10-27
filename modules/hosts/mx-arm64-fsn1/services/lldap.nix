{
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    { config, pkgs, ... }:
    let
      groups = [
        "org-asta-vorstand"
        "org-asta-informatik"
        "mail-testing"
      ];

      bootstrapScript =
        pkgs.writeText "lldap-declarative-groups.nu"
          # Nu
          ''
            def main [] {
              let port = "${toString config.services.lldap.settings.http_port or "17170"}"
              let base_url = $"http://127.0.0.1:($port)"

              # Injected with systemd LoadCredential
              let creds_dir = ($env.CREDENTIALS_DIRECTORY? | default "")
              let admin_pass = if ($creds_dir != "" and ($"($creds_dir)/admin_password" | path exists)) {
                open $"($creds_dir)/admin_password" | str trim
              } else {
                error make { msg: "Admin password credential not found" }
              }

              # Poll health check
              print "Waiting for LLDAP"
              loop {
                let is_ok = (try { (http get $"($base_url)/api/v1/health" | metadata | get http_response.status) == 200 } catch { false })
                if $is_ok { break }
                sleep 1sec
              }

              print "Authenticating with LLDAP"
              let login_res = ({
                username: "admin"
                password: $admin_pass
                } | to json | http post $"($base_url)/auth/simple/login" $in --content-type application/json)
              let token = $login_res.token
              let auth_headers = { Authorization: $"Bearer ($token)" }

              let gql_query = ({ query: "query { groups { displayName } }" } | to json)
              let existing = (
                http post $"($base_url)/api/graphql" $gql_query --headers $auth_headers --content-type application/json
                | get -o data.groups.displayName
                | default []
              )

              # Target list from Nix
              let targets = ${builtins.toJSON groups}
              let missing = ($targets | where {|g| $g not-in $existing})

              if ($missing | is-empty) {
                print "Nothing to do."
              } else {
                $missing | each {|group|
                  print $"Creating group: ($group)"
                  let mutation = ({
                    query: "mutation Create($name: String!) { createGroup(name: $name) { id displayName } }"
                    variables: { name: $group }
                  } | to json)
                  http post $"($base_url)/api/graphql" $mutation --headers $auth_headers --content-type application/json
                }
              }
            }
          '';
    in
    {
      services.lldap = {
        enable = true;
        database.type = "sqlite";
        environmentFile = config.sops.templates."lldap.env".path;

        settings = {
          ldap_host = "127.0.0.1";
          ldap_port = 3890;

          ldap_base_dn = "dc=asta-hs-mainz,dc=de";
          ldap_user_dn = "admin";
          ldap_user_email = "postmaster@asta-hs-mainz.de";
          ldap_user_pass_file = config.sops.secrets."lldap/admin_password".path;
          force_ldap_user_pass_reset = "always";

          http_host = "127.0.0.1";
          http_port = 17170;
          http_url = "https://lldap.asta-hs-mainz.de";

          jwt_secret_file = config.sops.secrets."lldap/jwt_secret".path;
        };
      };

      users.users.lldap = {
        isSystemUser = true;
        group = "lldap";
        extraGroups = [ "authelia" ];
      };
      users.groups.lldap = { };

      sops.secrets = {
        "lldap/jwt_secret" = {
          owner = "lldap";
          group = "lldap";
          restartUnits = [ "lldap.service" ];
        };

        "lldap/key_seed" = {
          owner = "lldap";
          group = "lldap";
          restartUnits = [ "lldap.service" ];
        };

        "lldap/admin_password" = {
          owner = "lldap";
          group = "lldap";
          restartUnits = [
            "lldap.service"
            "lldap-bootstrap.service"
            "stalwart.service"
          ];
        };
      };

      sops.templates."lldap.env" = {
        owner = "lldap";
        group = "lldap";
        content = ''
          LLDAP_KEY_SEED=${config.sops.placeholder."lldap/key_seed"}
        '';
      };

      systemd.services.lldap-bootstrap = {
        description = "Declaratively sets groups in LLDAP";
        after = [ "lldap.service" ];
        requires = [ "lldap.service" ];
        wantedBy = [ "multi-user.target" ];

        restartTriggers = [ bootstrapScript ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.nushell}/bin/nu ${bootstrapScript}";
          LoadCredential = [
            "admin_password:${config.sops.secrets."lldap/admin_password".path}"
          ];

          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
}
