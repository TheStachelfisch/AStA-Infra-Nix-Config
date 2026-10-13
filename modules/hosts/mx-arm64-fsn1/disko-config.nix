{ inputs, ... }:
{
  flake.modules.nixos.mx-arm64-fsn1 = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = "/dev/sdb";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP";
                start = "1M";
                end = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot/efi";
                  mountOptions = [ "umask=0077" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
        blob-storage = {
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/data/blob-storage";
            mountOptions = [
              "defaults"
              "noatime"
            ];
          };
        };
      };
    };
  };
}
