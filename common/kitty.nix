{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = mkIf isLinux [
      pkgs.kitty
    ];
    homebrew.casks = mkIf isDarwin [
      {
        name = "kitty";
        args = {
          no_quarantine = true;
        };
      }
    ];
    home-manager.users.agindin.home.file.".config/kitty/kitty.conf".source = ./kitty/kitty.conf;
  };
}

