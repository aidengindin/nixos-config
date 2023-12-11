{ pkgs, ... }:
{
  imports = [
    ./home.nix
  ];

  # Make sure the Nix daemon always runs
  services.nix-daemon.enable = true;

  programs.zsh.enable = true;
}
