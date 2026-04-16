{ pkgs, ... }:
pkgs.python3Packages.buildPythonPackage {
  pname = "intervals-mcp-server";
  version = "0.1.0";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "mvilanova";
    repo = "intervals-mcp-server";
    rev = "d95c790bee8fe66ccb9b0b4fe210308dfa576cc4";
    hash = "sha256-4RsrR/2Xy+AWOqHgL6u/zWlMOakgIJ8i+kYnD3iEwn0=";
  };

  build-system = [ pkgs.python3Packages.hatchling ];

  dependencies = with pkgs.python3Packages; [
    mcp
    httpx
    python-dotenv
  ];
}
