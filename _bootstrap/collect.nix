# Thin eval: load the module tree and extract only input declarations.
# Returns { declaredInputs, outputsExpr, description }
{
  lib,
  importTree,
  modulesPath,
}:
let
  eval = lib.evalModules {
    modules = [
      (importTree modulesPath)
      ./options.nix
    ];
  };

  cfg = eval.config.collect;

  # Filter out empty-url + non-follows inputs (they're incomplete)
  declaredInputs = lib.filterAttrs (
    _: spec: spec.url != "" || spec.follows != null
  ) cfg.inputs;
in
{
  inherit declaredInputs;
  outputsExpr = cfg.outputs-expr;
  description = cfg.description;
}
