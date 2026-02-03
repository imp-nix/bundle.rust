/**
  Rust bundle: package(s), devShell, and formatter.

  Uses rust-toolchain.toml if present, otherwise config.nightlyDate + config.targets.
  Consumes buildDeps from other bundles. Auto-detects linker deps from .cargo/config.toml.

  Single package mode (backwards compat):
    packages = {};  # builds root crate as "rust" package

  Multi-package mode:
    packages.cli = {};                     # pname = "cli", inherits base config
    packages.server.build.doCheck = true;  # override base config
*/
{
  __inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  __inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  __functor =
    _:
    {
      pkgs,
      lib ? pkgs.lib,
      inputs,
      rootSrc,
      config,
      buildDeps ? { },
      ...
    }:
    let
      rustPkgs = pkgs.extend inputs.rust-overlay.overlays.default;
      cargoToml = fromTOML (builtins.readFile (rootSrc + "/Cargo.toml"));
      toolchainFile = rootSrc + "/rust-toolchain.toml";

      rustToolchain =
        let
          base =
            if builtins.pathExists toolchainFile then
              rustPkgs.rust-bin.fromRustupToolchainFile toolchainFile
            else
              rustPkgs.rust-bin.nightly.${config.nightlyDate}.default;
        in
        if config.targets == [ ] then base else base.override { targets = config.targets; };

      rustPlatform = pkgs.makeRustPlatform {
        cargo = rustToolchain;
        rustc = rustToolchain;
      };

      cargoConfigDeps = import ./cargo-config.nix { inherit pkgs rootSrc; };
      depsValues = builtins.attrValues buildDeps;

      # Merge base build config with package-specific overrides
      mkPackageConfig =
        name: pkgCfg:
        lib.recursiveUpdate {
          pname = name;
          inherit (config) build;
        } pkgCfg;

      # Build a package from merged config
      mkPackage =
        name: pkgCfg:
        let
          cfg = mkPackageConfig name pkgCfg;
          pname = if cfg.build.pname != null then cfg.build.pname else cfg.pname;
          hasPostInstall = cfg.build.postInstall != "";
          isMultiPackage = config.packages != { };
        in
        rustPlatform.buildRustPackage (
          {
            inherit pname;
            version = (cargoToml.workspace.package or { }).version or (cargoToml.package or { }).version or "0.0.0";
            src = rootSrc;
            cargoLock = {
              lockFile = rootSrc + "/Cargo.lock";
              outputHashes =
                cfg.build.cargoOutputHashes
                // lib.foldl' (a: d: a // (d.cargoOutputHashes or { })) { } depsValues;
            };
            buildInputs = cargoConfigDeps.buildInputs ++ lib.concatMap (d: d.buildInputs or [ ]) depsValues;
            nativeBuildInputs =
              cargoConfigDeps.nativeBuildInputs
              ++ lib.optional hasPostInstall pkgs.makeWrapper
              ++ lib.concatMap (d: d.nativeBuildInputs or [ ]) depsValues;
            doCheck = cfg.build.doCheck;
          }
          // lib.optionalAttrs isMultiPackage {
            cargoBuildFlags = [ "-p" pname ];
            cargoTestFlags = [ "-p" pname ];
          }
          // lib.optionalAttrs hasPostInstall {
            inherit (cfg.build) postInstall;
          }
        );

      # Determine which packages to build
      packages =
        if config.packages == { } then
          # Backwards compat: single "rust" package from root Cargo.toml
          let
            rootPname = (cargoToml.package or { }).name or "rust";
          in
          {
            rust = mkPackage "rust" { pname = rootPname; };
          }
        else
          lib.mapAttrs mkPackage config.packages;

      # Build proper __outputs structure for each package
      packageOutputs = lib.foldl' lib.recursiveUpdate { } (
        lib.mapAttrsToList (
          name: pkg:
          lib.recursiveUpdate
            (lib.setAttrByPath [ "__outputs" "perSystem" "packages" name ] pkg)
            (lib.setAttrByPath [ "__outputs" "perSystem" "checks" name ] pkg)
        ) packages
      );
    in
    lib.recursiveUpdate packageOutputs {
      __outputs.perSystem.buildDeps.rust = {
        inherit rustToolchain rustPlatform rustPkgs;
      };

      __outputs.perSystem.devShells.rust = pkgs.mkShell {
        packages =
          [ rustToolchain pkgs.rust-analyzer pkgs.cargo-watch pkgs.cargo-edit ]
          ++ cargoConfigDeps.nativeBuildInputs
          ++ config.devShell.extraPackages;
      };

      __outputs.perSystem.formatter = {
        value = import ./formatter.nix { inherit pkgs; };
        strategy = "merge";
      };
    };
}
