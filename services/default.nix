{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./calibre.nix
    ./ollama.nix
    ./restic.nix
    ./ryot.nix
    ./wallabag.nix
  ];
}

