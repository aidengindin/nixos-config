{ config, pkgs, ... }:

{
  imports = [
    ./audiobookshelf.nix
    ./blocky.nix
    ./caddy.nix
    ./calibre.nix
    ./freshrss.nix
    ./grafana.nix
    ./immich.nix
    ./memos.nix
    ./miniflux.nix
    ./ollama.nix
    ./openwebui.nix
    ./pocket-id.nix
    ./postgres.nix
    ./prometheusExporter.nix
    ./promtail.nix
    ./restic.nix
    ./searxng.nix
    ./tandoor.nix
    ./withings-sync.nix
  ];
}

