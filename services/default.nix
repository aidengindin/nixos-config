{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./caddy.nix
    ./calibre.nix
    ./freshrss.nix
    ./immich.nix
    ./miniflux.nix
    ./ollama.nix
    ./restic.nix
    ./ryot.nix
    ./tandoor.nix
    ./wallabag.nix
  ];
}

