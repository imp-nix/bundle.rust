/**
  Rust bundle: package, check, and formatter config.

  Self-contained Rust tooling using rust-overlay.
  Uses rust-toolchain.toml if present, otherwise defaults to pinned nightly.
  Consumes buildDeps from other bundles for package builds.
  Formatter config imported from ./formatter.nix.
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
      lib ? pkgs.lib,
      inputs,
      rootSrc,
      buildDeps ? { },
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

      # Collect build dependencies from all bundles
      allBuildInputs = lib.concatMap (d: d.buildInputs or [ ]) (builtins.attrValues buildDeps);
      allNativeBuildInputs = lib.concatMap (d: d.nativeBuildInputs or [ ]) (builtins.attrValues buildDeps);
      allCargoOutputHashes = lib.foldl' (acc: d: acc // (d.cargoOutputHashes or { })) { } (builtins.attrValues buildDeps);
    in
    let
      package = rustPlatform.buildRustPackage {
        inherit pname version;
        src = rootSrc;
        cargoLock = {
          lockFile = rootSrc + "/Cargo.lock";
          outputHashes = allCargoOutputHashes;
        };
        buildInputs = allBuildInputs;
        nativeBuildInputs = allNativeBuildInputs;
        doCheck = false;
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
        value = import ./formatter.nix { inherit pkgs; };
        strategy = "merge";
      };
    };
}
