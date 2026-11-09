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
        "${inputs.nixpkgs-bulwark-update}/nixos/modules/services/web-apps/bulwark.nix"
      ];

      services.bulwark = {
        enable = true;
        package =
          (inputs.nixpkgs-bulwark-update.legacyPackages.${pkgs.system}.bulwark).overrideAttrs
            (oldAttrs: {
              preBuild = ''
                ${oldAttrs.preBuild or ""}
                node scripts/build-plugin-sandbox.mjs
              '';
            });
        plugins = with inputs.nixpkgs-bulwark-update.legacyPackages.${pkgs.system}.bulwark-plugins; [
          {
            package = team-inbox;
          }
          # {
          # package = languagetool;
          # Add again when self-hosting language-tool
          # }
          {
            package = reply-all-guardrail;
            # Add config limit of 5
          }
        ];
        admin = {
          passwordHashFile = config.sops.secrets."bulwark/admin_password".path;
        };
        updateCheck.enabled = false; # Disabled because it displays it in the login page for everyone
        settings = {
          jmapServerUrl = "https://mail.${domain}";
          sessionSecretFile = config.sops.secrets."bulwark/session_secret".path;

          branding.appName = "Webmail des AStA der Hochschule Mainz";
          appShortName = "Webmail AStA HSMZ";
          appDescription = "Offizieller Webmailer für den AStA, StuPa und Fachschaften der Hochschule Mainz.";
          loginCompanyName = "AStA Hochschule Mainz";
          loginWebsiteUrl = "https://asta-hs-mainz.de/";
          loginUsernamePlaceholder = "max.mustermann";
          accountManagementUrl = "https://auth.asta-hs-mainz.de/";
          accountManagementLabel = "Passwort Ändern";
          allowCustomJmapEndpoint = false;

          nextPublicDefaultLocale = "de";

          settingsSyncEnabled = true;
          pluginSigningKeyFile = config.sops.secrets."bulwark/plugin_signing_key".path;
        };
        policies = {
          features = {
            pluginsEnabled = true;
            filesEnabled = false;
            crossUnreadViewEnabled = true;
            crossStarredViewEnabled = true;
            crossAllViewEnabled = true;
            unifiedCrossAccountEnabled = true;
          };
          restrictions = {
            delegation.hidden = true;
            proofreading = {
              value = true;
              locked = true;
            };
          };
          organisation = {
            externalMail = {
              senderLabel = true;
              domains = [ "hs-mainz.de" ];
            };
            retention =
              let
                millis2days = millis: millis / 1000 / 60 / 60 / 24;
              in
              {
                trashDays = millis2days config.services.stalwart.provision.singletons.DataRetention.expungeTrashAfter;
                junkDays = millis2days config.services.stalwart.provision.singletons.DataRetention.expungeTrashAfter;
              };
          };
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
        "bulwark/plugin_signing_key" = {
          owner = "bulwark";
          group = "bulwark";
          restartUnits = [ "bulwark.service" ];
        };
      };
    };
}
