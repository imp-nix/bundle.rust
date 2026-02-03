{
  nightlyDate = "2026-01-21";
  targets = [ ];
  devShell.extraPackages = [ ];

  # Base build config - inherited by all packages unless overridden
  build.pname = null;
  build.doCheck = false;
  build.postInstall = "";
  build.cargoOutputHashes = { };

  # Multi-package support
  # Empty: single "rust" package built from root Cargo.toml (backwards compat)
  # Populated: each key becomes a package, inheriting base build config
  #
  # Example:
  #   packages.cli = {};                        # pname = "cli"
  #   packages.server.pname = "my-server";      # explicit pname
  #   packages.server.build.doCheck = true;     # override base
  packages = { };
}
