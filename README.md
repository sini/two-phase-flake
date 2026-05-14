# two-phase-flake

Module-driven flake input resolution with a real, overridable flake interface.

## Why not npins / nixlock / with-inputs?

These tools bypass the flake input system — they fetch sources at eval time from a side-channel lock file. You lose `nix flake lock`, `follows`, `--override-input`, `nix flake metadata`, and downstream input deduplication.

## Why not just flake-file's write-flake?

flake-file generates a real `flake.nix` from module declarations. But evaluation is blocked until you run the generation step — you can't `nix eval` until the inputs exist in `flake.nix`. The generation step is a prerequisite, not an optimization.

## What this does differently

Two-phase-flake combines both approaches with a hybrid resolver:

- **Always evaluable** — a pure userspace flake evaluator (`eval-flake.nix`) resolves inputs from `inputs.lock` via `builtins.fetchTree`, walking the dependency graph the same way Nix's flake evaluator does. No bootstrap prerequisite.
- **Real flake interface** — `nix run .#bootstrap` materializes a `flake.nix` with all inputs declared as real flake inputs. After this, `follows`, `--override-input`, and `nix flake metadata` all work.
- **Override wins** — the resolver prefers real flake inputs over the lock. Downstream overrides take effect automatically.

```
                    resolve.nix
                   ┌──────────────────────────────────┐
                   │ for each declared input:          │
flakeInputs ──────▶  present? → use it (real)         │──▶ allInputs
                   │  absent?  → evalFlake (from lock) │
inputs.lock ──────▶                                    │
                   └──────────────────────────────────┘
```

## eval-flake.nix — pure userspace flake evaluator

The `eval-flake.nix` library replicates what `builtins.getFlake` does, purely:

1. `builtins.fetchTree` with locked narHash (deterministic, no `--impure`)
2. Read `flake.lock` to get the dependency graph
3. Recursively resolve inputs by walking the lock graph
4. `import flake.nix` and call `.outputs` with resolved inputs

This means fetched flakes get their full dependency tree resolved — not just a flat `fetchTree`, but proper recursive evaluation with follows and sub-inputs.

```nix
# Evaluate any flake purely, given its source tree
(import ./eval-flake.nix).evalFlake (builtins.fetchTree {
  type = "github"; owner = "vic"; repo = "flake-file";
  rev = "04ca28cf..."; narHash = "sha256-...";
})
# => { flakeModules = ...; lib = ...; templates = ...; }
```

## Lifecycle

```bash
# 1. Start from seed — everything works immediately via evalFlake
cp seed-flake.nix flake.nix
nix eval .#packages.x86_64-linux.hello.name  # works

# 2. Bootstrap — promote to real flake inputs for the external interface
nix run .#bootstrap
nix flake lock

# 3. Now downstream consumers can follows/override your inputs
# inputs.two-phase.inputs.home-manager.follows = "home-manager";
```

## Adding an input

1. Declare it in any module:

```nix
# modules/my-feature.nix
{ lib, ... }:
{
  flake-file.inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

2. Lock it for evalFlake fallback, then optionally bootstrap for real flake inputs:

```bash
nix run .#update-lock   # writes inputs.lock
nix run .#bootstrap     # materializes flake.nix (optional — eval works without this)
nix flake lock          # pins real inputs
```

## Project structure

```
├── flake.nix          # Materialized (generated) or seed
├── seed-flake.nix     # Minimal seed — copy to flake.nix to start fresh
├── outputs-expr.nix   # Shared outputs logic (used by both seed and generated)
├── eval-flake.nix     # Pure userspace flake evaluator library
├── resolve.nix        # Input resolver: real flake input or evalFlake fallback
├── inputs.lock        # Locked narHash/rev for evalFlake resolution
└── modules/
    ├── inputs.nix     # Input declarations via flake-file.inputs
    └── outputs.nix    # Flake outputs
```

## How the resolver works

`resolve.nix` takes the set of real flake inputs and the lock file, then for each declared input:

1. **Real flake input available?** Use it. `--override-input` and `follows` from downstream take effect.
2. **Lock entry available?** Fetch the source tree with `builtins.fetchTree`, then:
   - If the fetched flake has its own `flake.lock`: use `evalFlake` for full recursive resolution, with follows patched to point at seed inputs.
   - Otherwise: simple eval — call `.outputs` with follows resolved directly.
3. **Neither?** Input is unavailable (outputs referencing it fail lazily).

## Design properties

- **Always evaluable** — seed flake works via evalFlake, no bootstrap needed
- **Real flake interface** — after bootstrap, inputs are real with full ecosystem support
- **Override wins** — resolver prefers flake inputs, so `--override-input` and `follows` work
- **Pure recursive resolution** — evalFlake walks the full dependency graph, no `--impure`
- **Module tree is source of truth** — flake-file.inputs declarations drive everything
- **Progressive** — start with seed (evalFlake), bootstrap when you need the external interface

## Requirements

- Nix with flakes enabled
- Seed inputs: [`nixpkgs`](https://github.com/NixOS/nixpkgs), [`import-tree`](https://github.com/vic/import-tree), [`flake-file`](https://github.com/vic/flake-file)

## License

MIT
