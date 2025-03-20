{ config, pkgs, ... }:
{
  imports = [
    ./bash.nix
    ./cli.nix
    ./direnv.nix
    ./emacs.nix
    ./git.nix
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
}
