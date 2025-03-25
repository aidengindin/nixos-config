{ config, pkgs, ... }:
{
  imports = [
    ./agenix.nix
    ./bash.nix
    ./bitwarden.nix
    ./cli.nix
    ./direnv.nix
    ./emacs.nix
    ./git.nix
    ./java.nix
    ./kitty.nix
    ./latex.nix
    ./mpv.nix
    ./nix.nix
    ./node.nix
    ./nvim.nix
    ./spotify.nix
    ./starship.nix
    ./zellij.nix
    ./zoxide.nix
  ];

  config = {
    users.users.agindin = {
      name = "agindin";
    };
    environment.systemPackages = with pkgs; [
      jq
    ];
  };
}
