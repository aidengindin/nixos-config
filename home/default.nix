{ config, pkgs, ... }:
{
  imports = [];

  config.users.users.agindin.name = "agindin";
  
  config.home-manager.users.agindin = {
    
    home.stateVersion = "23.11";
    
    # home.username = "agindin";

    programs.git = {
      enable = true;
      userName = "Aiden Gindin";
      userEmail = "aiden@aidengindin.com";
    };
  };
}
