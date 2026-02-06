# Rust Bundle

Nix bundle for building Rust packages, devShells, and formatting.

## Features

- Automatic toolchain from `rust-toolchain.toml` or configurable nightly date
- Single or multi-package builds from Cargo workspaces
- Auto-detection of linker dependencies from `.cargo/config.toml`
- Shares `rustPlatform` via `buildDeps` for other bundles to consume
- Integrated `treefmt` formatter with `rustfmt`

## Outputs

| Output | Description |
|--------|-------------|
| `packages.<name>` | Built Rust package(s) |
| `checks.<name>` | Same as packages (build verification) |
| `devShells.rust` | Shell with toolchain, rust-analyzer, cargo-watch, cargo-edit, wasm-bindgen-cli |
| `buildDeps.rust` | `{ rustToolchain, rustPlatform, rustPkgs }` for other bundles |
| `formatter` | Merges rustfmt into treefmt config |

## Configuration

### Base Config

```nix
# config.nix (defaults)
{
  nightlyDate = "2026-01-21";       # Fallback if no rust-toolchain.toml
  targets = [ ];                    # Extra rustup targets
  devShell.extraPackages = [ ];     # Additional devShell packages

  # Build config - inherited by all packages
  build.pname = null;               # Override package name (null = auto-detect)
  build.doCheck = false;            # Run cargo test
  build.postInstall = "";           # Post-install script (enables makeWrapper)
  build.cargoOutputHashes = { };    # Git dependency hashes

  # Multi-package mode (empty = single "rust" package)
  packages = { };
}
```

### Single Package Mode

When `packages = { }` (default), builds a single package named `rust` from the root `Cargo.toml`:

```nix
# rust.config.nix
{
  build.doCheck = true;
}
```

Outputs: `packages.rust`, `checks.rust`

### Multi-Package Mode

When `packages` is populated, each key becomes a separate package:

```nix
# rust.config.nix
{
  build.doCheck = true;              # Base: applies to all packages

  packages = {
    cli = { };                       # pname = "cli", inherits base config

    server = {
      build.pname = "my-server";     # Explicit pname override
      build.postInstall = ''
        wrapProgram $out/bin/my-server \
          --prefix PATH : ${lib.makeBinPath [ pkgs.ffmpeg ]}
      '';
    };

    internal = {
      build.doCheck = false;         # Override: skip tests for this package
    };
  };
}
```

Outputs: `packages.cli`, `packages.server`, `packages.internal` (plus corresponding checks)

## Config Inheritance

Package-specific config is merged over base config using `lib.recursiveUpdate`:

```
Base config (config.build.*)
    ↓ recursiveUpdate
Package config (packages.<name>.build.*)
    ↓
Final merged config for that package
```

Example:
```nix
{
  build.doCheck = true;           # Base: run tests
  build.cargoOutputHashes = {     # Base: shared git deps
    "git+https://..." = "sha256-...";
  };

  packages = {
    cli = { };                    # Inherits doCheck=true, cargoOutputHashes

    server = {
      build.doCheck = false;      # Override: no tests
      # Still inherits cargoOutputHashes
    };

    lib = {
      build.cargoOutputHashes = { # Override: different git deps
        "git+https://other..." = "sha256-...";
      };
      # Still inherits doCheck=true
    };
  };
}
```

## Consuming buildDeps

Other bundles can use the shared Rust toolchain:

```nix
# another-bundle/default.nix
{ buildDeps, rootSrc, ... }:
let
  inherit (buildDeps.rust) rustPlatform;
in {
  __outputs.perSystem.packages.my-tool = rustPlatform.buildRustPackage {
    pname = "my-tool";
    src = rootSrc + "/tools/my-tool";
    cargoLock.lockFile = rootSrc + "/Cargo.lock";
  };
}
```

## Toolchain Selection

Priority:
1. `rust-toolchain.toml` in project root (if exists)
2. `config.nightlyDate` nightly build

Additional targets can be added via `config.targets`:

```nix
{
  targets = [ "wasm32-unknown-unknown" "aarch64-unknown-linux-gnu" ];
}
```

## Linker Auto-Detection

The bundle reads `.cargo/config.toml` and automatically adds required native dependencies for custom linkers (e.g., `mold`, `lld`).
