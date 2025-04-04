{ config, pkgs, ... }:

{
  imports = [
    ./blocky.nix
    ./caddy.nix
    ./calibre.nix
    ./freshrss.nix
    ./immich.nix
    ./memos.nix
    ./miniflux.nix
    ./ollama.nix
    ./openwebui.nix
    ./restic.nix
    ./searxng.nix
    ./tandoor.nix
    ./withings-sync.nix
  ];
}

