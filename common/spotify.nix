{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.spotify;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.spotify = {
    enable = mkEnableOption "spotify-player";
  };
  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.spotify-player = {
      enable = true;
      package = unstablePkgs.spotify-player;
    };
  };
}

