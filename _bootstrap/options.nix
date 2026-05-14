# Module options for input collection (thin eval schema)
{ lib, ... }:
{
  options.collect = {
    inputs = lib.mkOption {
      description = "Declared flake inputs to be materialized";
      type = lib.types.lazyAttrsOf (
        lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
          options = {
            url = lib.mkOption {
              description = "Flake input URL";
              type = lib.types.str;
              default = "";
            };
            flake = lib.mkOption {
              description = "Whether this input is a flake";
              type = lib.types.bool;
              default = true;
            };
            follows = lib.mkOption {
              description = "Input to follow";
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            inputs = lib.mkOption {
              description = "Sub-input follows";
              type = lib.types.lazyAttrsOf lib.types.anything;
              default = { };
            };
          };
        }
      );
      default = { };
    };

    outputs-expr = lib.mkOption {
      description = "Nix expression string for the flake outputs function";
      type = lib.types.str;
      default = ''
        inputs:
          let
            importTree = import inputs.import-tree;
          in
          (inputs.nixpkgs.lib.evalModules {
            specialArgs = { inherit inputs; inherit (inputs) self; };
            modules = [ (importTree ./modules) ./_bootstrap/options.nix ];
          }).config.outputs
      '';
    };

    description = lib.mkOption {
      description = "Flake description";
      type = lib.types.str;
      default = "";
    };
  };

  options.outputs = lib.mkOption {
    description = "Flake outputs (evaluated in phase 2 only)";
    type = lib.types.listOf lib.types.raw;
    default = [ ];
    apply = list: lib.foldl' lib.recursiveUpdate { } list;
  };
}
