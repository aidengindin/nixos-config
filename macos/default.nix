{ config, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./librewolf.nix
    ./nix.nix
  ];

  users.users.agindin.home = "/Users/agindin";
}
