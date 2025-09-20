{ config, pkgs, ... }:

{
  imports = [
    ./audiobookshelf.nix
    ./blocky.nix
    ./caddy.nix
    ./calibre.nix
    ./freshrss.nix
    ./immich.nix
    ./jellyfin.nix
    ./memos.nix
    ./miniflux.nix
    ./ollama.nix
    ./openwebui.nix
    ./pinchflat.nix
    ./pocket-id.nix
    ./restic.nix
    ./searxng.nix
    ./tandoor.nix
    ./withings-sync.nix
  ];
}

