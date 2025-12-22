{ pkgs, agenix, ... }:
{
  imports = [
    ./bash.nix
    ./cli.nix
    ./dev.nix
    ./direnv.nix
    ./git.nix
    ./kitty.nix
    ./latex.nix
    ./mpv.nix
    ./neomutt.nix
    ./nix.nix
    ./nvim.nix
    ./opencode.nix
    ./spotify.nix
    ./starship.nix
    ./yazi.nix
    ./zoxide.nix
  ];

  config = {
    home-manager.users.agindin.programs.home-manager.enable = true;
    environment.systemPackages = [
      agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
