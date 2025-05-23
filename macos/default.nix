{ config, pkgs, ... }:
{
  imports = [
    ./homebrew.nix
    ./librewolf.nix
    ./kitty.nix
    ./nix.nix
    ./yabai.nix
  ];

  users.users.agindin.home = "/Users/agindin";

  age.identityPaths = [
    "/Users/agindin/.ssh/id_ed25519"
  ];

  system.primaryUser = "agindin";

  ids.gids.nixbld = 30000;
}
