# This is the minimal seed flake.nix you start from.
# It only needs nixpkgs + import-tree. Running `nix run .#bootstrap`
# will replace it with a full flake.nix containing all declared inputs.
{
  description = "Two-phase flake: thin eval collects inputs, bootstrap materializes them";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    import-tree = {
      url = "github:vic/import-tree";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, import-tree, self, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      importTree = import import-tree;

      # Thin eval: collect input declarations without requiring them
      collected = import ./_bootstrap/collect.nix {
        inherit lib importTree;
        modulesPath = ../modules;
      };

      missingInputs = builtins.filter (n: !(inputs ? ${n})) (
        builtins.attrNames collected.declaredInputs
      );

      allSatisfied = missingInputs == [ ];

      flakeSource = import ./_bootstrap/render.nix {
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

      fullOutputs =
        (lib.evalModules {
          specialArgs = {
            inherit inputs;
            inherit (inputs) self;
          };
          modules = [
            (importTree ../modules)
            ./options.nix
          ];
        }).config.outputs;

      bootstrapApp =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          flakeFile = pkgs.writeText "flake-source.nix" flakeSource;
          bootstrap = pkgs.writeShellApplication {
            name = "bootstrap";
            runtimeInputs = [ pkgs.nixfmt-rfc-style ];
            text = ''
              cp ${flakeFile} flake.nix
              nixfmt flake.nix
              echo "flake.nix regenerated. Next: nix flake lock"
            '';
          };
        in
        {
          type = "app";
          program = lib.getExe bootstrap;
        };
    in
    if allSatisfied then
      fullOutputs
      // {
        apps = eachSystem (system: {
          bootstrap = bootstrapApp system;
        });
      }
    else
      {
        apps = eachSystem (system: {
          default = bootstrapApp system;
          bootstrap = bootstrapApp system;
        });
        missing = missingInputs;
        collected = collected.declaredInputs;
      };
}
