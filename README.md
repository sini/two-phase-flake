# two-phase-flake

A self-bootstrapping Nix flake that collects input declarations from a module tree and materializes them into `flake.nix` — no external tooling required.

## The problem

Nix flakes require all inputs to be declared statically in `flake.nix`. In modular projects, the set of required inputs is determined by which modules are active — but you can't evaluate modules without first having the inputs they need.

## The solution

Two-phase evaluation:

1. **Phase 1 (thin eval):** A seed flake with only `nixpkgs` + `import-tree` evaluates the module tree, forcing only pure data declarations (`collect.inputs`). This determines what inputs are needed without requiring them to exist yet.

2. **Phase 2 (full eval):** After bootstrap regenerates `flake.nix` with all declared inputs and `nix flake lock` pins them, the same module tree provides real outputs through `evalModules`.

## Getting started

```bash
# Clone and enter
git clone https://github.com/sini/two-phase-flake
cd two-phase-flake

# Phase 1: bootstrap generates flake.nix with all declared inputs
nix run .#bootstrap

# Lock the new inputs
nix flake lock

# Phase 2: full eval works
nix eval .#packages.x86_64-linux.hello.name
# => "hello-2.12.3"
```

## Adding inputs

Declare inputs anywhere in your module tree:

```nix
# modules/my-feature.nix
{ lib, ... }:
{
  collect.inputs.some-flake = {
    url = "github:owner/repo";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then re-bootstrap:

```bash
nix run .#bootstrap
nix flake lock --update-input some-flake
```

## Project structure

```
├── flake.nix                # Generated — don't edit by hand
├── _bootstrap/
│   ├── options.nix          # Module options schema (collect.inputs, outputs)
│   ├── collect.nix          # Thin eval: extracts input declarations
│   └── render.nix           # Nix source code generator
└── modules/
    ├── inputs.nix           # Input declarations (phase 1)
    ├── outputs.nix          # Real outputs (phase 2)
    └── bootstrap.nix        # Keeps bootstrap app available after phase 2
```

## How it works internally

### Thin eval (`_bootstrap/collect.nix`)

Runs `lib.evalModules` on the module tree with only the `collect` options defined. Since Nix is lazy, output definitions that reference unavailable inputs are never forced — only `config.collect.inputs` (pure data) is evaluated.

### Rendering (`_bootstrap/render.nix`)

Takes the collected input specs and serializes them into valid Nix source with proper escaping, dotted-key notation for simple inputs, and `follows` declarations.

### The seed flake

The initial `flake.nix` (before first bootstrap) detects which declared inputs are missing from the actual flake inputs. If any are missing, it exposes only the bootstrap app. If all are satisfied, it does the full `evalModules` and exposes real outputs.

### Output merging

Modules contribute to `config.outputs` as a list of attrsets, merged with `lib.recursiveUpdate`. This allows multiple modules to provide outputs without conflicts:

```nix
# modules/my-outputs.nix
{ inputs, lib, ... }:
{
  outputs = [{
    packages.x86_64-linux.my-thing = ...;
  }];
}
```

## Design properties

- **Zero external dependencies** — bootstrap logic is self-contained in `_bootstrap/`
- **Module tree is source of truth** — both input declarations and outputs live in `modules/`
- **Lazy phase separation** — thin eval never forces outputs that need unavailable inputs
- **Idempotent** — re-running bootstrap with unchanged modules produces the same file
- **Incremental** — add inputs in any module, re-bootstrap, lock, done

## Requirements

- Nix with flakes enabled
- Only `nixpkgs` and [`import-tree`](https://github.com/vic/import-tree) as seed inputs

## License

MIT
