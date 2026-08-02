{ pkgs, ... }:
pkgs.python3Packages.buildPythonPackage {
  pname = "intervals-mcp-server";
  version = "0-unstable-2026-05-21";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "mvilanova";
    repo = "intervals-mcp-server";
    rev = "7512cdf8f75dda9784f2dea3d4c2c93d2b33df54";
    hash = "sha256-mXJbdcj3atKnbpa2E9o30E6SJqw9JPT4EmA8wLwxn64=";
  };

  build-system = [ pkgs.python3Packages.hatchling ];

  dependencies = with pkgs.python3Packages; [
    mcp
    httpx
    python-dotenv
  ];
}
