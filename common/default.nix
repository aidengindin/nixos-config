{ config, pkgs, ... }:
{
  imports = [
    ./bash.nix
    ./cli.nix
    ./direnv.nix
    ./emacs.nix
    ./java.nix
    ./kitty.nix
    ./latex.nix
    ./nix.nix
    ./nvim.nix
    ./starship.nix
    ./zellij.nix
    ./zoxide.nix
  ];

  config.users.users.agindin = {
    name = "agindin";
  };

  config.home-manager.users.agindin = {
    programs.git = {
      enable = true;
      userName = "Aiden Gindin";
      userEmail = "aiden@aidengindin.com";
      delta.enable = true;
      lfs.enable = true;
    };
  };
}
