/**
  Rust bundle: package, devShell, and formatter.

  Uses rust-toolchain.toml if present, otherwise config.nightlyDate + config.targets.
  Consumes buildDeps from other bundles. Auto-detects linker deps from .cargo/config.toml.
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

      hasPostInstall = config.build.postInstall != "";

      package = rustPlatform.buildRustPackage (
        {
          pname = if config.pname != null then config.pname else cargoToml.package.name;
          version = cargoToml.workspace.package.version or cargoToml.package.version;
          src = rootSrc;
          cargoLock = {
            lockFile = rootSrc + "/Cargo.lock";
            outputHashes =
              config.build.cargoOutputHashes
              // lib.foldl' (a: d: a // (d.cargoOutputHashes or { })) { } depsValues;
          };
          buildInputs = cargoConfigDeps.buildInputs ++ lib.concatMap (d: d.buildInputs or [ ]) depsValues;
          nativeBuildInputs =
            cargoConfigDeps.nativeBuildInputs
            ++ lib.optional hasPostInstall pkgs.makeWrapper
            ++ lib.concatMap (d: d.nativeBuildInputs or [ ]) depsValues;
          doCheck = config.build.doCheck;
        }
        // lib.optionalAttrs hasPostInstall {
          inherit (config.build) postInstall;
        }
      );
    in
    {
      __outputs.perSystem.buildDeps.rust = {
        inherit rustToolchain rustPlatform rustPkgs;
      };

      __outputs.perSystem.packages.rust = package;
      __outputs.perSystem.checks.rust = package;

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
