/**
  Rust bundle: package, check, and formatter config.

  Self-contained Rust tooling using rust-overlay.
  Uses rust-toolchain.toml if present, otherwise defaults to pinned nightly.
  Formatter fragments merge with other formatter.d/ or __outputs.formatter contributions.
*/
{
  __inputs = {
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor =
    _:
    {
      pkgs,
      inputs,
      rootSrc,
      ...
    }:
    let
      rustPkgs = pkgs.extend inputs.rust-overlay.overlays.default;
      cargoToml = fromTOML (builtins.readFile (rootSrc + "/Cargo.toml"));
      pname = cargoToml.package.name or (baseNameOf rootSrc);
      version = cargoToml.workspace.package.version or cargoToml.package.version;
      toolchainFile = rootSrc + "/rust-toolchain.toml";
      rustToolchain =
        if builtins.pathExists toolchainFile then
          rustPkgs.rust-bin.fromRustupToolchainFile toolchainFile
        else
          rustPkgs.rust-bin.nightly."2026-01-21".default;
      rustPlatform = pkgs.makeRustPlatform {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };

      /**
        Wrapper for cargo-sort to work with treefmt.
        treefmt passes file paths, but cargo-sort operates on directories.
      */
      cargoSortWrapper = pkgs.writeShellScriptBin "cargo-sort-wrapper" ''
        set -euo pipefail
        opts=(); files=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --*) opts+=("$1"); shift ;;
            *) files+=("$1"); shift ;;
          esac
        done
        for f in "''${files[@]}"; do
          ${pkgs.lib.getExe pkgs.cargo-sort} "''${opts[@]}" "$(dirname "$f")"
        done
      '';
    in
    let
      package = rustPlatform.buildRustPackage {
        inherit pname version;
        src = rootSrc;
        cargoLock.lockFile = rootSrc + "/Cargo.lock";
      };
    in
    {
      __outputs.perSystem.packages.rust = package;

      /**
        Rust build check.
        Runs tests via doCheck.
      */
      __outputs.perSystem.checks.rust = package;

      /**
        Rust development shell with toolchain and common tools.
      */
      __outputs.perSystem.devShells.rust = pkgs.mkShell {
        packages = [
          rustToolchain
          pkgs.rust-analyzer
          pkgs.cargo-watch
          pkgs.cargo-edit
        ];
      };

      /**
        Formatter config fragment.
        Merges with other formatter.d/ or __outputs.formatter sources.
      */
      __outputs.perSystem.formatter = {
        value = {
          programs.rustfmt.enable = true;
          settings.formatter.cargo-sort = {
            command = "${cargoSortWrapper}/bin/cargo-sort-wrapper";
            options = [ "--workspace" ];
            includes = [
              "Cargo.toml"
              "**/Cargo.toml"
            ];
          };
        };
        strategy = "merge";
      };
    };
}
