{ pkgs, ... }:
{
  imports = [
    ./home.nix
  ];

  # Make sure the Nix daemon always runs
  services.nix-daemon.enable = true;

  # Since this isn't Linux, we can't depend on this being set in system
  programs.zsh.enable = true;

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
        experimental-features = nix-command flakes
      '';            
  };
}
