{ config, ... }:
{
  imports = [
    ./desktop.nix
    ./firefox.nix
  ];

  config.home-manager.users.agindin = {
    home.stateVersion = "23.11";
    programs.git = {
      enable = true;
      userName = "Aiden Gindin";
      userEmail = "aiden@aidengindin.com";
    };
  };
}
