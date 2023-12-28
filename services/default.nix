{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./blocky.nix
    ./ryot.nix
    ./wallabag.nix
  ];
}

