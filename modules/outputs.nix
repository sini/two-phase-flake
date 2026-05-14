# Real outputs — only evaluated in phase 2 when all inputs are available.
# Uses a custom option to avoid flake-file's submodule-wrapped `outputs`.
{ inputs, lib, ... }:
{
  options.flake-outputs = lib.mkOption {
    description = "Raw flake outputs attrset (bypasses flake-file submodule wrapping)";
    type = lib.types.listOf lib.types.raw;
    default = [ ];
    apply = list: lib.foldl' lib.recursiveUpdate { } list;
  };

  config.flake-outputs = [
    {
      packages =
        lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
            "x86_64-darwin"
            "aarch64-darwin"
          ]
          (system: {
            hello = inputs.nixpkgs.legacyPackages.${system}.hello;
          });
    }
  ];
}
