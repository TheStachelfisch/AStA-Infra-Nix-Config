{
  inputs,
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 = {
    imports = with inputs.self.modules.nixos; [
      system-server
    ];

    networking.hostName = "mx-arm64-fsn1";
  };
}
