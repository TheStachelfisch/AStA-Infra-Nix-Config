{
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    { config, ... }:
    let
      baseDn = config.services.lldap.settings.ldap_base_dn;
      domain = "asta-hs-mainz.de";

      mkAutheliaSecret = {
        owner = config.services.authelia.instances.main.user;
        group = config.services.authelia.instances.main.group;
        restartUnits = [ "authelia-main.service" ];
      };
    in
    {
      services.authelia.instances.main = {
        enable = true;

        secrets = {
          jwtSecretFile = config.sops.secrets."authelia/jwt_secret".path;
          sessionSecretFile = config.sops.secrets."authelia/session_secret".path;
          storageEncryptionKeyFile = config.sops.secrets."authelia/storage_encryption_key".path;
          oidcHmacSecretFile = config.sops.secrets."authelia/oidc_hmac_secret".path;
          oidcIssuerPrivateKeyFile = config.sops.secrets."authelia/oidc_issuer_private_key".path;
        };

        environmentVariables = {
          AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
            config.sops.secrets."authelia/lldap_bind_password".path;
          #AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = config.sops.secrets."authelia/smtp_password".path;
        };

        settings = {
          theme = "auto";
          default_2fa_method = "totp";

          log.level = "debug";

          # Server
          server.address = "tcp://127.0.0.1:9091/";

          # First Factor
          authentication_backend = {
            refresh_interval = "1m";
            password_reset.disable = false;
            password_change.disable = false;

            ldap = {
              implementation = "lldap";
              address = "ldap://127.0.0.1:3890";
              timeout = "5s";
              start_tls = false;
              base_dn = baseDn;

              additional_users_dn = "ou=people";
              users_filter = "(&({username_attribute}={input})(objectClass=person))";

              additional_groups_dn = "ou=groups";
              groups_filter = "(member={dn})";

              user = "uid=admin,ou=people,${baseDn}";

              # attributes set by default by the implementation
            };
          };

          # Second Factor
          totp = {
            disable = false;
            issuer = "AStA HS Mainz (${domain})";
          };

          # Security
          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = "auth.${domain}";
                policy = "bypass";
              }
              {
                domain = [
                  "*.${domain}"
                  domain
                ];
                policy = "two_factor";
              }
            ];
          };

          password_policy = {
            standard.enabled = false;
            zxcvbn = {
              enabled = true;
              min_score = 3;
            };
          };

          # Session
          session = {
            name = "authelia_session";
            same_site = "lax";
            inactivity = "4h";
            expiration = "7d";
            remember_me = "30d";
            cookies = [
              {
                domain = domain;
                authelia_url = "https://auth.${domain}";
                default_redirection_url = "https://mail.${domain}"; # TODO: Change me
              }
            ];
          };

          # Storage
          storage.local.path = "/var/lib/authelia-main/db.sqlite3";

          # Notifications
          notifier = {
            disable_startup_check = false;
            filesystem.filename = "/var/lib/authelia-main/notifications.txt";
          };

          # Identity Providers
          identity_providers.oidc = {
            lifespans = {
              authorize_code = "1m";
              access_token = "1h";
              id_token = "1h";
              refresh_token = "30d";
            };

            cors = {
              endpoints = [
                "authorization"
                "token"
                "revocation"
                "introspection"
                "userinfo"
              ];
              allowed_origins = [ "https://mail.${domain}" ];
            };

            clients = [
              {
                client_id = "test-client";
                client_name = "OIDC Test Playground";
                public = true; # No client_secret needed (uses PKCE)
                authorization_policy = "two_factor"; # Tests your 2FA flow
                redirect_uris = [
                  "https://oauth.tools/callback"
                  "https://oidcdebugger.com/debug"
                ];
                scopes = [
                  "openid"
                  "profile"
                  "email"
                  "groups"
                ];
                response_types = [ "code" ];
                grant_types = [ "authorization_code" ];
                response_modes = [
                  "query"
                  "form_post"
                ];
              }
            ];
          };
        };
      };

      services.nginx = {
        enable = true;
        virtualHosts."auth.${domain}" = {
          forceSSL = true;
          useACMEHost = "asta-hs-mainz.de";
          locations."/" = {
            proxyPass = "http://127.0.0.1:9091";
            extraConfig = ''
              proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $http_host;
              proxy_set_header X-Forwarded-URI $request_uri;
              proxy_set_header X-Forwarded-Ssl on;
              proxy_set_header X-Forwarded-For $remote_addr;
            '';
          };
        };
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      sops.secrets = {
        "authelia/jwt_secret" = mkAutheliaSecret;
        "authelia/session_secret" = mkAutheliaSecret;
        "authelia/storage_encryption_key" = mkAutheliaSecret;
        "authelia/oidc_hmac_secret" = mkAutheliaSecret;
        "authelia/oidc_issuer_private_key" = mkAutheliaSecret;

        "authelia/lldap_bind_password" = {
          key = "lldap/admin_password";
          owner = config.services.authelia.instances.main.user;
          group = config.services.authelia.instances.main.group;
          restartUnits = [ "authelia-main.service" ];
        };
      };
    };
}
