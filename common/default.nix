{ config, pkgs, ... }:
{
  imports = [
    ./bash.nix
    ./bitwarden.nix
    ./cli.nix
    ./direnv.nix
    ./emacs.nix
    ./git.nix
    ./java.nix
    ./kitty.nix
    ./latex.nix
    ./nix.nix
    ./node.nix
    ./nvim.nix
    ./starship.nix
    ./zellij.nix
    ./zoxide.nix
  ];

  config.users.users.agindin = {
    name = "agindin";
  };
}
