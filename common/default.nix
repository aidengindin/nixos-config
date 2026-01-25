{ pkgs, agenix, ... }:
{
  imports = [
    ./bash.nix
    ./cli.nix
    ./claude-code.nix
    ./dev.nix
    ./direnv.nix
    ./git.nix
    ./kitty.nix
    ./latex.nix
    ./mpv.nix
    ./neomutt.nix
    ./nvim.nix
    ./opencode.nix
    ./spotify.nix
    ./starship.nix
    ./vesktop.nix
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
