# Real outputs — only evaluated in phase 2 when all inputs are available.
{ inputs, lib, ... }:
{
  outputs = [{
    # Example: expose a simple package
    packages =
      lib.genAttrs
        [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ]
        (
          system:
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          {
            hello = pkgs.hello;
          }
        );
  }];
}
