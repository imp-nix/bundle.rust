/**
  Rust formatter configuration for treefmt.

  Provides rustfmt and cargo-sort integration.
*/
{ pkgs }:
let
  inherit (pkgs) lib;
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
{
  programs.rustfmt.enable = true;
  settings.formatter.rustfmt.options = lib.mkAfter [
    "--config"
    "hard_tabs=true,imports_granularity=Module,group_imports=StdExternalCrate"
  ];
  settings.formatter.cargo-sort = {
    command = "${cargoSortWrapper}/bin/cargo-sort-wrapper";
    options = [ "--workspace" ];
    includes = [
      "Cargo.toml"
      "**/Cargo.toml"
    ];
  };
}
