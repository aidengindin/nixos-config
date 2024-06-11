{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./ollama.nix
    ./restic.nix
    ./ryot.nix
    ./wallabag.nix
  ];
}

