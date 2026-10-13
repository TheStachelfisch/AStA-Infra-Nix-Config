{ ... }:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    {
      lib,
      modulesPath,
      pkgs,
      ...
    }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "virtio_pci"
        "virtio_scsi"
        "usbhid"
        "sr_mod"
      ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.efiSysMountPoint = "/boot/efi";
      boot.loader.efi.canTouchEfiVariables = true;

      boot.kernelPackages = pkgs.linuxPackages_latest;

      zramSwap = {
        enable = true;
        memoryPercent = 20;
      };

      nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    };
}
