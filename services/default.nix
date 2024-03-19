{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./restic.nix
    ./ryot.nix
    ./wallabag.nix
  ];
}

