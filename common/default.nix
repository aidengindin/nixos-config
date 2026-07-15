{ pkgs, agenix, ... }:
{
  imports = [
    ./bash.nix
    ./cli.nix
    ./claude-code.nix
    ./claude-desktop.nix
    ./codex.nix
    ./mcp.nix
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
    ./yazi.nix
    ./zoxide.nix
  ];

  config = {
    home-manager.users.agindin.programs.home-manager.enable = true;
    # Without useGlobalPkgs, home-manager builds its own separate, unconfigured pkgs
    # instance internally. Packages referenced from specialArgs (e.g. unstablePkgs.claude-code
    # in claude-code.nix) still evaluate fine on their own, but anything home-manager itself
    # constructs from them (e.g. programs.claude-code's symlinkJoin wrapper) re-runs the
    # unfree/insecure check against this internal pkgs, so it needs the same config.
    home-manager.users.agindin.nixpkgs.config = pkgs.config;
    environment.systemPackages = [
      agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
