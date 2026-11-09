{
  inputs,
  lib,
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    { config, pkgs, ... }:
    let
      domain = "asta-hs-mainz.de";
      acmeCertDir = config.security.acme.certs.${domain}.directory;

      mkStalwartSecret = {
        owner = config.services.stalwart.user;
        group = config.services.stalwart.group;
        restartUnits = [ "stalwart.service" ];
      };
    in
    {
      disabledModules = [ "services/mail/stalwart.nix" ];
      imports = [
        "${inputs.nixpkgs-stalwart}/nixos/modules/services/mail/stalwart/"
        "${inputs.nixpkgs-stalwart}/nixos/modules/services/mail/stalwart/provision.nix"
      ];
      # TODO: Remove once https://github.com/NixOS/nixpkgs/pull/552103#discussion_r4373195056 is resolved
      nixpkgs.overlays = [
        (final: prev: {
          stalwart-cli = pkgs.unstable.stalwart-cli;
        })
      ];

      services.stalwart = {
        enable = true;
        stateVersion = "26.11";
        package = pkgs.unstable.stalwart_1_0;
        openFirewall = false; # TODO: Open port manually

        url = "https://mail.${domain}"; # TODO: Uncomment for public release
        admin = {
          enable = true;
          username = "admin";
        };
        credentials.admin = config.sops.secrets."stalwart/admin_password".path;

        provision =
          let
            variant = type: value: { "@type" = type; } // value;
          in
          {
            enable = true;
            reloadSettings = true;
            package = pkgs.unstable.stalwart-cli;
            url = "http://127.0.0.1:8080/";
            singletons = {
              SystemSettings = {
                defaultHostname = "mail.${domain}";
                defaultDomainId = "#testing-domain";
                defaultCertificateId = "#main-certificate";
              };

              Cache = {
                directoryRecipientsTtl = 60000;
              };

              DataRetention = {
                expungeTrashAfter = 2592000000;
              };

              BlobStore = variant "FileSystem" {
                path = "/data/blob-storage/stalwart-blobs";
              };

              DataStore = variant "RocksDb" {
                path = "/var/lib/stalwart/db";
              };

              Authentication = {
                directoryId = "#lldap-directory";
              };

              Http.usePermissiveCors = true;

              DnsResolver = variant "System" { };
              MtaSts = {
                mode = "enforce";
              };

              Search = {
                defaultLanguage = "de-DE";
              };

              SpamPyzor = {
                enable = true;
              };
            };
            objects = {
              Tracer = {
                reconcile = true;
                match = [ "@type" ];
                objects = {
                  stdout = variant "Stdout" {
                    level = "warn";
                  };
                };
              };
              NetworkListener = {
                reconcile = true;
                match = [ "name" ];
                objects = {
                  listener-mgmt = {
                    name = "management";
                    protocol = "http";
                    bind = [ "[::]:8080" ];
                    implicitTls = false;
                  };
                  listener-smtp-relay = {
                    name = "relay";
                    protocol = "smtp";
                    bind = [ "[::]:25" ];
                    implicitTls = false;
                  };
                  listener-smtp-submission = {
                    name = "submission";
                    protocol = "smtp";
                    bind = [ "[::]:465" ];
                    implicitTls = true;
                  };
                  listener-imap = {
                    name = "imap";
                    protocol = "imap";
                    bind = [ "[::]:993" ];
                    implicitTls = true;
                  };
                  listener-pop3 = {
                    name = "pop3";
                    protocol = "pop3";
                    bind = [ "[::]:995" ];
                    implicitTls = true;
                  };
                  listener-sieve = {
                    name = "sieve";
                    protocol = "manageSieve";
                    bind = [ "[::]:4190" ];
                    implicitTls = false;
                  };
                };
              };
              Domain = {
                reconcile = true;
                match = [ "name" ];
                objects = {
                  main-domain = {
                    name = domain;
                    enable = false;
                    dnsManagement = variant "Manual" { };
                    subAddressing = variant "Enabled" { };
                    certificateManagement = variant "Manual" { };
                    dkimManagement = variant "Automatic" (
                      let
                        days2millis = days: days * 24 * 60 * 60 * 1000;
                      in
                      {
                        selectorTemplate = "v{version}-{algorithm}-{date-%Y%m%d}";
                        rotateAfter = days2millis 90;
                        retireAfter = days2millis 7;
                        deleteAfter = days2millis 30;
                      }
                    );
                  };
                  testing-domain = {
                    name = "mail.${domain}";
                    enable = true;
                    dnsManagement = variant "Automatic" {
                      dnsServerId = "#cloudflare-dns";
                      origin = "asta-hs-mainz.de";
                    };
                    subAddressing = variant "Enabled" { };
                    certificateManagement = variant "Manual" { };
                    dkimManagement = variant "Automatic" (
                      let
                        days2millis = days: days * 24 * 60 * 60 * 1000;
                      in
                      {
                        selectorTemplate = "v{version}-{algorithm}-{date-%Y%m%d}";
                        rotateAfter = days2millis 90;
                        retireAfter = days2millis 7;
                        deleteAfter = days2millis 30;
                      }
                    );
                  };
                };
              };
              DnsServer = {
                reconcile = true;
                match = [ "@type" ];
                objects = {
                  cloudflare-dns = variant "Cloudflare" {
                    secret = variant "File" {
                      filePath = config.sops.secrets."stalwart/cloudflare_dns_api_key".path;
                    };
                    description = "Cloudflare DNS asta-hs-mainz.de";
                  };
                };
              };
              Certificate = {
                reconcile = true;
                match = [ "certificate" ];
                objects = {
                  main-certificate = {
                    certificate = variant "File" {
                      filePath = "${acmeCertDir}/fullchain.pem";
                    };
                    privateKey = variant "File" {
                      filePath = "${acmeCertDir}/key.pem";
                    };
                  };
                };
              };
              Directory = {
                reconcile = true;
                match = [
                  "description"
                  "url"
                ];
                objects = {
                  lldap-directory = variant "Ldap" {
                    description = "LLDAP Directory";
                    url = "ldap://${config.services.lldap.settings.ldap_host}:${toString config.services.lldap.settings.ldap_port}";
                    useTls = false;
                    allowInvalidCerts = false;
                    baseDn = config.services.lldap.settings.ldap_base_dn;
                    bindDn = "uid=admin,ou=people,${config.services.lldap.settings.ldap_base_dn}";

                    bindSecret = variant "File" {
                      filePath = config.sops.secrets."stalwart/lldap_admin_password".path;
                    };

                    filterLogin = "(&(objectClass=person)(|(uid=?)(mail=?)))";
                    filterRecipient = "(|(&(objectClass=person)(|(uid=?)(mail=?)))(&(objectClass=groupOfUniqueNames)(|(cn=?)(mail=?))))";
                    groupClass = "groupOfUniqueNames";
                    filterMemberOf = "(&(objectClass=groupOfUniqueNames)(member=?))";

                    attrDescription = [ "displayName" ];
                    attrEmail = [ "mail" ];
                    attrEmailAlias = [ ];
                    attrSecret = [ ];
                    attrSecretChanged = [ ];
                  };
                };
              };
            };
          };
      };

      networking.firewall.allowedTCPPorts = [
        25
        465
        993
        995
        4190
      ];

      systemd.services.stalwart.serviceConfig.ReadWritePaths = [ "/data/blob-storage/stalwart-blobs" ];

      # For ACME certificate
      users.users.${config.services.stalwart.user}.extraGroups = [ "nginx" ];

      security.acme.certs.${domain}.reloadServices = [
        "stalwart.service"
        "stalwart-provision.service"
      ];

      services.nginx =
        let
          commonHostConfig = {
            forceSSL = true;
            useACMEHost = domain;

            locations."/" = {
              proxyPass = "http://127.0.0.1:8080";
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
        in
        {
          enable = true;
          virtualHosts."mail.${domain}" = commonHostConfig;
          virtualHosts."mta-sts.mail.${domain}" = commonHostConfig;
          virtualHosts."autodiscover.mail.${domain}" = commonHostConfig;
          virtualHosts."autoconfig.mail.${domain}" = commonHostConfig;
          virtualHosts."ua-auto-config.mail.${domain}" = commonHostConfig;
        };

      sops.secrets = {
        "stalwart/lldap_admin_password" = {
          key = "lldap/admin_password";
          owner = config.services.stalwart.user;
          group = config.services.stalwart.group;
          restartUnits = [
            "stalwart.service"
            "stalwart-provision.service"
          ];
        };

        "stalwart/admin_password" = mkStalwartSecret;
        "stalwart/cloudflare_dns_api_key" = mkStalwartSecret;
      };
    };
}
