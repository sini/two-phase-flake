# Expose the bootstrap app in phase 2 outputs for re-generation.
{ inputs, lib, config, ... }:
let
  importTree = import inputs.import-tree;

  collected = import ../_bootstrap/collect.nix {
    inherit lib importTree;
    modulesPath = ../modules;
  };

  flakeSource = import ../_bootstrap/render.nix {
    inherit lib;
    seedInputs = {
      nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
      import-tree = {
        url = "github:vic/import-tree";
        flake = false;
      };
    };
    extraInputs = collected.declaredInputs;
    outputsExpr = collected.outputsExpr;
    inherit (collected) description;
  };

  eachSystem = lib.genAttrs [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  bootstrapApp =
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      flakeFile = pkgs.writeText "flake-source.nix" flakeSource;
      bootstrap = pkgs.writeShellApplication {
        name = "bootstrap";
        runtimeInputs = [ pkgs.nixfmt-rfc-style ];
        text = ''
          cp ${flakeFile} flake.nix
          nixfmt flake.nix
          echo "flake.nix regenerated."
          echo "Next: nix flake lock --update-input <new-input>"
        '';
      };
    in
    {
      type = "app";
      program = lib.getExe bootstrap;
    };
in
{
  outputs = [{
    apps = eachSystem (system: {
      bootstrap = bootstrapApp system;
    });
  }];
}
