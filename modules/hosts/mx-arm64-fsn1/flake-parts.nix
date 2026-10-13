{
  inputs,
  ...
}:
{
  flake.nixosConfigurations = inputs.self.lib.mkNixos "aarch64-linux" "mx-arm64-fsn1";
}
