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
    package = nixVersions.stable;
    extraOptions = ''
        experimental-features = nix-command flakes
      '';
      optimise = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 1;
          Minute = 0;
        };
      };
      gc = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 0;
          Minute = 0;
        };
        options = "--delete-older-than 30d";
      };
  };

  environment.systemPackages = with pkgs; [
    ollama
  ];

  system.stateVersion = 5;
}
