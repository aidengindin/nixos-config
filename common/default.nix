{ config, pkgs, ... }:
{
  imports = [
    ./agenix.nix
    ./bash.nix
    ./bitwarden.nix
    ./claude-code.nix
    ./cli.nix
    ./dev.nix
    ./direnv.nix
    ./emacs.nix
    ./git.nix
    ./java.nix
    ./kitty.nix
    ./latex.nix
    ./mpv.nix
    ./neomutt.nix
    ./nix.nix
    ./node.nix
    ./nvim.nix
    ./spotify.nix
    ./starship.nix
    ./yazi.nix
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
