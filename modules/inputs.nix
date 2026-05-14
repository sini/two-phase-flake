# Declare flake inputs via flake-file's typed option system.
# These are collected during thin eval and materialized into flake.nix.
{ lib, ... }:
{
  flake-file.inputs = {
    nixpkgs.url = lib.mkDefault "github:nixos/nixpkgs/nixpkgs-unstable";

    import-tree = {
      url = lib.mkDefault "github:vic/import-tree";
      flake = false;
    };

    flake-file.url = lib.mkDefault "github:vic/flake-file";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  flake-file.description = "Two-phase flake: synthetic thin eval collects inputs, bootstrap materializes a real flake";
}
