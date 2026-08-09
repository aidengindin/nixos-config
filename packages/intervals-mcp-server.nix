{ pkgs, ... }:
pkgs.python3Packages.buildPythonPackage {
  pname = "intervals-mcp-server";
  version = "0-unstable-2026-08-02";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "mvilanova";
    repo = "intervals-mcp-server";
    rev = "cb1fbcac81095cf3e094e995decf04b8b1f259f8";
    hash = "sha256-YSE1YdOAlz4+IsEbwIHpcR9N7ngFfHqYjxGbYkti8OA=";
  };

  build-system = [ pkgs.python3Packages.hatchling ];

  dependencies = with pkgs.python3Packages; [
    mcp
    httpx
    python-dotenv
  ];
}
