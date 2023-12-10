{ config, ... }:
{
  imports = [
    ./firefox.nix
  ];

  config.home-manager.users.agindin = {
    home.stateVersion = "23.11";
  };

  config.programs.git = {
    enable = true;
    userName = "Aiden Gindin";
    userEmail = "aiden@aidengindin.com";
  };
}
