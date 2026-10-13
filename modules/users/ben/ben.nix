{
  self,
  lib,
  ...
}:
let
  username = "ben";
in
{
  flake.modules = lib.mkMerge [
    (self.factory.user "${username}" true)
    {
      nixos."${username}" =
        { config, ... }:
        {
          users.users.${username} = {
            hashedPasswordFile = config.sops.secrets."user_passwords/ben".path;
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF11N4SUplaakwU3LWzf1IcGIunXaP97vK1UXVLX3skt"
            ];
          };

          sops.secrets."user_passwords/ben" = {
            neededForUsers = true;
          };
        };
      homeManager."${username}" = {
        imports = with self.modules.homeManager; [
          system-cli
        ];
      };
    }
  ];
}
