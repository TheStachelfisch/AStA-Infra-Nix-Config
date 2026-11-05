{
  flake.modules.nixos.acme = { config, ... }: {
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "vorstand@asta-hs-mainz.de";
        dnsProvider = "cloudflare";
        environmentFile = config.sops.secrets."cloudflare/dns_api_token".path;
      };

      certs."asta-hs-mainz.de" = {
        extraDomainNames = [
          "*.asta-hs-mainz.de"
          "*.mail.asta-hs-mainz.de"
        ];
        group = "nginx";
        reloadServices = [ "nginx.service" ];
      };
    };

    sops.secrets."cloudflare/dns_api_token" = { };
  };
}
