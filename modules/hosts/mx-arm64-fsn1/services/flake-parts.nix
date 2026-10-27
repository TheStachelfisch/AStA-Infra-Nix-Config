{ inputs, ... }:
{
  flake-file.inputs = {
    nixpkgs-stalwart.url = "github:0x57e11a/nixpkgs/9b15e1f0c8e848e0ac11d8c0ac2f6b3d7027799c";
  };

  imports = [ inputs.disko.flakeModules.default ];
}
