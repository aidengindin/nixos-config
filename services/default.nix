{ config, pkgs, ... }:

{
  imports = [
    ./arion.nix
    ./ryot.nix
    ./watchyourlan.nix
  ];
}

