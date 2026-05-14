# Input resolver: prefer real flake inputs, fall back to evalFlake from lock.
#
# For each declared input:
#   - If it exists in flakeInputs → use it (real flake input, overridable)
#   - If in lock → build a virtual lock graph and evalFlake it
#   - Otherwise → unavailable
#
# The evalFlake path walks the lock graph the same way Nix's flake
# evaluator does — fetchTree + import flake.nix + recursive resolution.
# Follows resolve against seed inputs.
{
  lib,
  flakeInputs,
  lockFile,
  declaredInputs,
}:
let
  inherit (import ./eval-flake.nix) evalFlake toLockGraph;

  lock = if builtins.pathExists lockFile then lib.importJSON lockFile else { };

  seedNames = [
    "nixpkgs"
    "import-tree"
    "flake-file"
  ];

  # Build a virtual flake.lock graph from our inputs.lock
  virtualLock = toLockGraph {
    inherit declaredInputs;
    lockData = lock;
    seedInputNames = seedNames;
  };

  # Add seed inputs as nodes so the graph can resolve follows to them
  seedNodes = lib.mapAttrs (name: _: {
    locked =
      {
        type = "github";
        owner = "";
        repo = "";
      }
      // (
        if flakeInputs ? ${name} && flakeInputs.${name} ? rev then
          {
            inherit (flakeInputs.${name}) rev;
            narHash = flakeInputs.${name}.narHash or "";
          }
        else
          { }
      );
  }) (lib.genAttrs seedNames (_: null));

  # Resolve a single input: flake input wins, evalFlake fallback
  resolveOne =
    name: _declSpec:
    if flakeInputs ? ${name} then
      flakeInputs.${name}
    else if lock ? ${name} then
      let
        lockSpec = lock.${name};
        tree = builtins.fetchTree lockSpec.locked;
        isFlake = lockSpec.flake or true;

        # For flake inputs: build a minimal lock graph for this input
        # and evaluate it with follows pointing to seed inputs
        followsResolved = lib.mapAttrs (
          _: target: flakeInputs.${target}
        ) (lockSpec.follows or { });

        flakeAttr = import "${tree}/flake.nix";

        # If the fetched flake has its own flake.lock, use evalFlake
        # for full recursive resolution. Otherwise, simple eval.
        hasOwnLock = builtins.pathExists "${tree}/flake.lock";

        fullEval =
          let
            ownLock = builtins.fromJSON (builtins.readFile "${tree}/flake.lock");

            # Inject our seed inputs as overrides for follows targets
            patchedNodes = ownLock.nodes // (
              lib.mapAttrs (
                inputName: target:
                let
                  seedInput = flakeInputs.${target};
                in
                {
                  # Point this node at the seed input's source
                  locked = {
                    type = seedInput.type or "github";
                    owner = seedInput.owner or "";
                    repo = seedInput.repo or "";
                    rev = seedInput.rev or "";
                    narHash = seedInput.narHash or "";
                  } // (lib.optionalAttrs (seedInput ? lastModified) {
                    inherit (seedInput) lastModified;
                  });
                  flake = true;
                }
              ) (lockSpec.follows or { })
            );
          in
          evalFlake {
            src = tree;
            lock = ownLock // { nodes = patchedNodes; };
          };

        simpleEval = flakeAttr.outputs (followsResolved // { self = tree; });

        evaluated = if hasOwnLock then fullEval else simpleEval;

        sourceAttrs =
          { outPath = tree.outPath; }
          // (lib.optionalAttrs (tree ? rev) { inherit (tree) rev; })
          // (lib.optionalAttrs (tree ? narHash) { inherit (tree) narHash; })
          // (lib.optionalAttrs (tree ? lastModified) { inherit (tree) lastModified; });
      in
      if isFlake then
        evaluated // sourceAttrs
      else
        tree
    else
      null;

  resolved = lib.mapAttrs resolveOne declaredInputs;
in
flakeInputs // (lib.filterAttrs (_: v: v != null) resolved)
