# The seed flake — copy this to flake.nix to start.
# Only needs nixpkgs + import-tree + flake-file as real inputs.
# Module-declared inputs are resolved via fetchTree from inputs.lock.
# Run `nix run .#bootstrap` to promote them to real flake inputs.
{
  description = "Two-phase flake: module-driven input resolution with overridable flake interface";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    import-tree = {
      url = "github:vic/import-tree";
      flake = false;
    };
    flake-file.url = "github:vic/flake-file";
  };

  outputs = flakeInputs: import ./outputs-expr.nix flakeInputs;
}
