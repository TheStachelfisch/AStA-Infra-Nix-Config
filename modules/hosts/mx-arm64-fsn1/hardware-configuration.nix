{ ... }:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    {
      lib,
      modulesPath,
      ...
    }:
    {
      zramSwap = {
        enable = true;
        memoryPercent = 20;
      };

      nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    };
}
