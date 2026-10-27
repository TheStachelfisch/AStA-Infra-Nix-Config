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
        package = pkgs.unstable.stalwart_0_16;
        openFirewall = false; # TODO: Open port manually

        url = "https://mail.${domain}";
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
                defaultDomainId = "#main-domain";
                defaultCertificateId = "#main-certificate";
              };
              Http.useXForwarded = true;

              BlobStore = variant "FileSystem" {
                path = "/data/blob-storage/stalwart-blobs";
              };

              DataStore = variant "RocksDb" {
                path = "/var/lib/stalwart/db";
              };

              Authentication = {
                directoryId = "#lldap-directory";
              };

              Imap = {

              };
            };
            objects = {
              Tracer = {
                reconcile = true;
                match = [ "@type" ];
                objects = {
                  stdout = variant "Stdout" {
                    level = "trace";
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
                    tlsImplicit = false;
                  };
                  listener-smtp-relay = {
                    name = "relay";
                    protocol = "smtp";
                    bind = [ "[::]:25" ];
                    tlsImplicit = false;
                  };
                  listener-smtp-submission = {
                    name = "submission";
                    protocol = "smtp";
                    bind = [ "[::]:465" ];
                    tlsImplicit = true;
                  };
                  listener-imap = {
                    name = "imap";
                    protocol = "imap";
                    bind = [ "[::]:993" ];
                    tlsImplicit = true;
                  };
                  listener-pop3 = {
                    name = "pop3";
                    protocol = "pop3";
                    bind = [ "[::]:995" ];
                    tlsImplicit = true;
                  };
                  listener-sieve = {
                    name = "sieve";
                    protocol = "manageSieve";
                    bind = [ "[::]:4190" ];
                    tlsImplicit = false;
                  };
                };
              };
              Domain = {
                reconcile = true;
                match = [ "name" ];
                objects = {
                  main-domain = {
                    name = domain;
                    isEnabled = true;
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
                    filterMailbox = "(|(&(objectClass=person)(uid=?))(&(objectClass=groupOfUniqueNames)(|(cn=?)(mail=?))))";
                    groupClass = "groupOfUniqueNames";
                    filterMemberOf = "(&(objectClass=groupOfUniqueNames)(member=?))";

                    attrEmail = [ "mail" ];
                  };
                };
              };
            };
          };
      };

      # For ACME certificate
      users.users.${config.services.stalwart.user}.extraGroups = [ "nginx" ];

      security.acme.certs.${domain}.reloadServices = [
        "stalwart.service"
        "stalwart-provision.service"
      ];

      services.nginx = {
        enable = true;
        virtualHosts."mail.${domain}" = {
          forceSSL = true;
          useACMEHost = domain;
        };
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
      };
    };
}
