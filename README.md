# two-phase-flake

Module-driven flake input resolution with a real, overridable flake interface.

## Why not npins / nixlock / with-inputs?

These tools bypass the flake input system — they fetch sources at eval time via `builtins.fetchTree` from a side-channel lock file. This means you lose `nix flake lock`, `follows`, `--override-input`, `nix flake metadata`, and downstream input deduplication.

## Why not just flake-file's write-flake?

flake-file generates a real `flake.nix` from module declarations. But evaluation is blocked until you run the generation step — you can't `nix eval` until `flake.nix` has the right inputs. The generation step is a prerequisite, not an optimization.

## What this does differently

Two-phase-flake combines both approaches:

- **fetchTree fallback** — evaluation always works, even from a seed flake with only nixpkgs + import-tree + flake-file. Missing inputs are resolved via `builtins.fetchTree` from `inputs.lock` (pure, uses narHash).
- **Real flake interface** — `nix run .#bootstrap` materializes a `flake.nix` with all inputs declared as real flake inputs. After this, `follows`, `--override-input`, and `nix flake metadata` all work.
- **Resolver prefers real inputs** — when a real flake input exists, it's used instead of fetchTree. Downstream overrides win automatically.

```
                    resolve.nix
                   ┌──────────────────────────────┐
                   │ for each declared input:      │
flakeInputs ──────▶  present? → use it (real)     │──▶ allInputs
                   │  absent?  → fetchTree (lock)  │
inputs.lock ──────▶                                │
                   └──────────────────────────────┘
```

## Lifecycle

```bash
# 1. Start from seed — everything works immediately via fetchTree
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

2. Lock it for fetchTree fallback, then bootstrap for real flake inputs:

```bash
nix run .#update-lock   # writes inputs.lock
nix run .#bootstrap     # materializes flake.nix
nix flake lock          # pins real inputs
```

## Project structure

```
├── flake.nix          # Materialized (generated) or seed
├── seed-flake.nix     # Minimal seed — copy to flake.nix to start fresh
├── outputs-expr.nix   # Shared outputs logic (used by both seed and generated)
├── resolve.nix        # Input resolver: real flake input or fetchTree fallback
├── inputs.lock        # Locked narHash/rev for fetchTree resolution
└── modules/
    ├── inputs.nix     # Input declarations via flake-file.inputs
    └── outputs.nix    # Flake outputs
```

## How the resolver works

`resolve.nix` takes the set of real flake inputs and the lock file, then for each declared input:

1. **Real flake input available?** Use it. This means `--override-input` and `follows` from downstream consumers take effect.
2. **Lock entry available?** `builtins.fetchTree` with the locked narHash (pure), then `import "${tree}/flake.nix"` and call `.outputs` with follows wired to seed inputs.
3. **Neither?** Input is unavailable (outputs referencing it will fail lazily).

This means the seed flake evaluates immediately (fetchTree mode), and after bootstrap the same code path uses real flake inputs instead — no behavior change, just better integration with the flake ecosystem.

## Design properties

- **Always evaluable** — seed flake works via fetchTree, no bootstrap prerequisite
- **Real flake interface** — after bootstrap, inputs are real flake inputs with full ecosystem support
- **Override wins** — resolver prefers flake inputs over lock, so `--override-input` and `follows` work
- **Module tree is source of truth** — flake-file.inputs declarations drive both fetchTree and bootstrap
- **Pure** — fetchTree with narHash is deterministic, no `--impure` needed

## Requirements

- Nix with flakes enabled
- Seed inputs: [`nixpkgs`](https://github.com/NixOS/nixpkgs), [`import-tree`](https://github.com/vic/import-tree), [`flake-file`](https://github.com/vic/flake-file)

## License

MIT
