{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./rustic.nix
    ./ryot.nix
    ./wallabag.nix
  ];
}

