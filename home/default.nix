{ config, pkgs, ... }:
{
  imports = [
    ./alacritty.nix
    ./emacs.nix
    ./eza.nix
    ./kitty.nix
    ./latex.nix
    ./zsh.nix
  ];

  config.users.users.agindin = {
    name = "agindin";
    shell = pkgs.zsh;
  };

  config.environment.shells = with pkgs; [ zsh bash ];
  
  config.home-manager.users.agindin = {
    
    home.stateVersion = "23.11";
    
    programs.git = {
      enable = true;
      userName = "Aiden Gindin";
      userEmail = "aiden@aidengindin.com";
    };
  };
}
