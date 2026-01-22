/**
  Cargo config dependency detection.

  Parses .cargo/config.toml to detect and provide required build tools.

  Supported configurations:
  - `linker = "clang"` or `linker = "gcc"` in [target.*] sections
  - `-fuse-ld=mold` or `-fuse-ld=lld` in rustflags arrays

  Example .cargo/config.toml:
    [target.x86_64-unknown-linux-gnu]
    linker = "clang"
    rustflags = ["-C", "link-arg=-fuse-ld=mold"]
*/
{ pkgs, rootSrc }:
let
  configPath = rootSrc + "/.cargo/config.toml";
  hasConfig = builtins.pathExists configPath;
  config = if hasConfig then fromTOML (builtins.readFile configPath) else { };

  targets = config.target or { };
  targetConfigs = builtins.attrValues targets;

  linkers = builtins.filter (x: x != null) (map (t: t.linker or null) targetConfigs);
  allRustflags = builtins.concatLists (map (t: t.rustflags or [ ]) targetConfigs);
  rustflagsStr = builtins.concatStringsSep " " allRustflags;

  linkerPackages =
    (if builtins.any (l: l == "clang" || pkgs.lib.hasPrefix "clang" l) linkers then [ pkgs.clang ] else [ ])
    ++ (if builtins.any (l: l == "gcc" || pkgs.lib.hasPrefix "gcc" l) linkers then [ pkgs.gcc ] else [ ]);

  ldPackages =
    (if builtins.match ".*-fuse-ld=mold.*" rustflagsStr != null then [ pkgs.mold ] else [ ])
    ++ (if builtins.match ".*-fuse-ld=lld.*" rustflagsStr != null then [ pkgs.lld ] else [ ]);
in
{
  buildInputs = [ ];
  nativeBuildInputs = linkerPackages ++ ldPackages;

  /**
    Introspection of detected configuration.
  */
  detected = {
    inherit hasConfig linkers;
    rustflags = allRustflags;
    packages = map (p: p.name or p.pname or "unknown") (linkerPackages ++ ldPackages);
  };
}
