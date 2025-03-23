{ config, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./librewolf.nix
    ./nix.nix
    ./yabai.nix
  ];

  users.users.agindin.home = "/Users/agindin";
}
