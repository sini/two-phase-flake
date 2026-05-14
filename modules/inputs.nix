# Declare additional flake inputs needed by this project.
# These are collected during thin eval (phase 1) and materialized into flake.nix.
{ lib, ... }:
{
  collect.inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

  };
}
