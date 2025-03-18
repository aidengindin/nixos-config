{ config, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./librewolf.nix
  ];
}
