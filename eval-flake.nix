# Pure userspace flake evaluator.
#
# Replicates what builtins.getFlake does, using only:
#   - builtins.fetchTree (pure with narHash)
#   - builtins.fromJSON / builtins.readFile (read flake.lock)
#   - import (load flake.nix)
#
# Walks the flake.lock dependency graph, recursively fetching and
# evaluating each input's flake.nix with its resolved inputs.
#
# Usage:
#   evalFlake ./path/to/flake
#   evalFlake (builtins.fetchTree { type = "github"; owner = "..."; ... })
#   evalFlake { src = ./.; lock = { nodes = ...; root = "root"; }; }
#
let
  evalFlake =
    arg:
    let
      # Accept either a path/store-path or an attrset with src + lock
      isStructured = builtins.isAttrs arg && arg ? src;
      src = if isStructured then arg.src else arg;
      lock =
        if isStructured && arg ? lock then
          arg.lock
        else
          builtins.fromJSON (builtins.readFile "${src}/flake.lock");

      flakeNix = import "${src}/flake.nix";
      nodes = lock.nodes or { };
      rootName = lock.root or "root";
      rootNode = nodes.${rootName} or { };

      # Resolve a follows path like ["nixpkgs"] or ["foo", "bar"]
      # by walking from the root node through the graph.
      resolveFollows =
        path:
        let
          walk =
            currentNodeName: remainingPath:
            if remainingPath == [ ] then
              resolveNode currentNodeName
            else
              let
                currentNode = nodes.${currentNodeName} or { };
                nextRef = (currentNode.inputs or { }).${builtins.head remainingPath} or null;
                rest = builtins.tail remainingPath;
              in
              if nextRef == null then
                throw "eval-flake: follows path ${builtins.toJSON path} unresolvable at ${currentNodeName}"
              else if builtins.isList nextRef then
                # Nested follows — resolve from root
                resolveFollows (nextRef ++ rest)
              else
                # Direct node reference
                walk nextRef rest;
        in
        walk rootName path;

      # Resolve a single input reference (string = node name, list = follows path)
      resolveRef =
        ref:
        if builtins.isList ref then resolveFollows ref else resolveNode ref;

      # Resolve and evaluate a node by name. Results are memoized by Nix's
      # lazy evaluation — each node is evaluated at most once.
      resolveNode =
        nodeName:
        let
          node = nodes.${nodeName} or { };
          isFlake = node.flake or true;
          hasLocked = node ? locked;

          tree = if hasLocked then builtins.fetchTree node.locked else src;

          # Recursively resolve this node's inputs
          nodeInputs = builtins.mapAttrs (_: resolveRef) (node.inputs or { });

          # Evaluate the flake
          nodeFlakeNix = import "${tree}/flake.nix";
          evaluated = nodeFlakeNix.outputs (nodeInputs // { self = tree; });

          # Preserve sourceInfo-like attrs from fetchTree
          sourceAttrs =
            {
              outPath = tree.outPath or tree;
            }
            // (if tree ? rev then { inherit (tree) rev; } else { })
            // (if tree ? narHash then { inherit (tree) narHash; } else { })
            // (if tree ? lastModified then { inherit (tree) lastModified; } else { });
        in
        if !hasLocked then
          # Root node or synthetic — skip fetch
          null
        else if isFlake then
          evaluated // sourceAttrs
        else
          tree;

      # Resolve the root's inputs
      rootInputs = builtins.mapAttrs (_: resolveRef) (rootNode.inputs or { });
    in
    flakeNix.outputs (rootInputs // { self = src; });

  # Construct a flake.lock-compatible structure from our inputs.lock format
  # and flake-file input declarations. This bridges between our lock format
  # and the standard flake.lock graph that evalFlake walks.
  toLockGraph =
    {
      declaredInputs,
      lockData,
      seedInputNames ? [
        "nixpkgs"
        "import-tree"
        "flake-file"
      ],
    }:
    let
      # Seed inputs become nodes that reference the real flake input
      # (evalFlake will be called with overrides for these)
      extraNames = builtins.filter (n: !(builtins.elem n seedInputNames)) (
        builtins.attrNames declaredInputs
      );

      # Build nodes from lock data
      extraNodes = builtins.listToAttrs (
        map (
          name:
          let
            entry = lockData.${name} or { };
            declEntry = declaredInputs.${name} or { };

            # Convert follows from our format { nixpkgs = "nixpkgs" }
            # to flake.lock format { nixpkgs = ["nixpkgs"] }
            followsAttrs = builtins.mapAttrs (_: target: [ target ]) (entry.follows or { });
          in
          {
            inherit name;
            value =
              {
                locked = entry.locked or { };
                flake = entry.flake or (declEntry.flake or true);
              }
              // (if followsAttrs != { } then { inputs = followsAttrs; } else { });
          }
        ) (builtins.filter (n: lockData ? ${n}) extraNames)
      );

      # Root node references all inputs
      allInputNames = seedInputNames ++ extraNames;
      rootInputs = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = name;
        }) (builtins.filter (n: extraNodes ? ${n} || builtins.elem n seedInputNames) allInputNames)
      );
    in
    {
      nodes = extraNodes // {
        root = {
          inputs = rootInputs;
        };
      };
      root = "root";
      version = 7;
    };
in
{
  inherit evalFlake toLockGraph;
}
