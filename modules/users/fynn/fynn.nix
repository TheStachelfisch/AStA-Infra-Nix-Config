{
  self,
  lib,
  ...
}:
let
  username = "fynn";
in
{
  flake.modules = lib.mkMerge [
    (self.factory.user "${username}" true)
    {
      nixos."${username}" =
        { config, ... }:
        {
          users.users.${username} = {
            hashedPasswordFile = config.sops.secrets."user_passwords/fynn".path;
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF/Q7Gug5cJ/J7d56e755UIFrJ8j24pHw8LiNuq0EFdM"
            ];
          };

          sops.secrets."user_passwords/fynn" = {
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
