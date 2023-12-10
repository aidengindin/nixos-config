{ config, ... }:
{
  imports = [
    ./firefox.nix
  ];

  config.home-manager.users.agindin = {
    home.stateVersion = "23.11";
  };
}
