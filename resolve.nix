# Input resolver: prefer real flake inputs, fall back to fetchTree from lock.
#
# For each declared input:
#   - If it exists in flakeInputs → use it (real flake input, overridable)
#   - If in lock file → fetchTree + eval its flake.nix
#   - Otherwise → unavailable
#
# Follows always resolve against flakeInputs (seed inputs), which are
# the authoritative source for shared dependencies like nixpkgs.
{
  lib,
  flakeInputs,
  lockFile,
  declaredInputs,
}:
let
  lock = if builtins.pathExists lockFile then lib.importJSON lockFile else { };

  # Fetch a source tree and evaluate it as a flake
  fetchAndEval = name: lockSpec:
    let
      tree = builtins.fetchTree lockSpec.locked;
      isFlake = lockSpec.flake or true;

      # Resolve follows against seed flake inputs (not recursive)
      followsResolved = lib.mapAttrs
        (_: target: flakeInputs.${target})
        (lockSpec.follows or { });

      flakeAttr = import "${tree}/flake.nix";
      evaluated = flakeAttr.outputs (followsResolved // { self = tree; });
    in
    if isFlake then
      evaluated // { outPath = tree.outPath; }
    else
      tree;

  resolveOne = name: _declSpec:
    if flakeInputs ? ${name} then
      flakeInputs.${name}
    else if lock ? ${name} then
      fetchAndEval name lock.${name}
    else
      null;

  resolved = lib.mapAttrs resolveOne declaredInputs;
in
flakeInputs
// (lib.filterAttrs (_: v: v != null) resolved)
