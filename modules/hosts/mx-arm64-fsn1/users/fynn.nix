{
  inputs,
  ...
}:
{
  flake.modules.nixos.mx-arm64-fsn1 =
    { ... }:
    {
      imports = with inputs.self.modules.nixos; [
        fynn
      ];

      home-manager.users.fynn = {
        imports = with inputs.self.modules.homeManager; [
          fynn
        ];
      };
    };
}
