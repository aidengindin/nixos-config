{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.spotify;
  inherit (lib) mkIf mkEnableOption;
  
  spotify-player-main = unstablePkgs.spotify-player.overrideAttrs (oldAttrs: rec {
    version = "main";
    src = pkgs.fetchFromGitHub {
      owner = "aome510";
      repo = "spotify-player";
      rev = "master";
      hash = "sha256-DCIZHAfI3x9I6j2f44cDcXbMpZbNXJ62S+W19IY6Qus=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "spotify-player-main";
      hash = "sha256-fNDztl0Vxq2fUzc6uLNu5iggNRnRB2VxzWm+AlSaoU0=";
    };
  });
in
{
  options.agindin.spotify = {
    enable = mkEnableOption "spotify-player";
  };
  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.spotify-player = {
      enable = true;
      package = spotify-player-main;
    };
  };
}

