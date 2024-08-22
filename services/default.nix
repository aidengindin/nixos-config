{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./authelia.nix
    ./blocky.nix
    ./caddy.nix
    ./calibre.nix
    ./freshrss.nix
    ./ollama.nix
    ./restic.nix
    ./ryot.nix
    ./tandoor.nix
    ./wallabag.nix
  ];
}

