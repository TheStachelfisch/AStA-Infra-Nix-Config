{
  inputs,
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    { pkgs, config, ... }:
    let
      domain = "asta-hs-mainz.de";
    in
    {
      imports = [
        "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/bulwark.nix"
      ];

      services.bulwark = {
        enable = true;
        package = pkgs.unstable.bulwark;
        admin = {
          passwordHashFile = config.sops.secrets."bulwark/admin_password".path;
        };
        settings = {
          jmapServerUrl = "https://mail.${domain}";
          sessionSecretFile = config.sops.secrets."bulwark/session_secret".path;
        };
      };

      services.nginx = {
        enable = true;

        virtualHosts."webmail.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;

          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.bulwark.port}";
            proxyWebsockets = true;
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

      sops.secrets = {
        "bulwark/admin_password" = {
          owner = "bulwark";
          group = "bulwark";
          restartUnits = [ "bulwark.service" ];
        };
        "bulwark/session_secret" = {
          owner = "bulwark";
          group = "bulwark";
          restartUnits = [ "bulwark.service" ];
        };
      };
    };
}
