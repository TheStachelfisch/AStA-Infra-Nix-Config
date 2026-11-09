{ inputs, ... }:
{
  flake-file.inputs = {
    nixpkgs-stalwart.url = "github:NixOS/nixpkgs/pull/552103/head";
    nixpkgs-bulwark-update.url = "github:NixOS/nixpkgs/pull/574920/head";
  };

  imports = [ inputs.disko.flakeModules.default ];
}
