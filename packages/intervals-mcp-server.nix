# `src` is the intervals-mcp-server flake input (flake = false), locked in
# flake.lock and bumped under the updater's 7-day cooldown.
{ pkgs, src, ... }:
let
  d = src.lastModifiedDate;
in
pkgs.python3Packages.buildPythonPackage {
  pname = "intervals-mcp-server";
  version = "0-unstable-${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
  pyproject = true;

  inherit src;

  build-system = [ pkgs.python3Packages.hatchling ];

  dependencies = with pkgs.python3Packages; [
    mcp
    httpx
    python-dotenv
  ];
}
