{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.spotify;
  inherit (lib) mkIf mkEnableOption;
  
  # spotify-player-main = unstablePkgs.spotify-player.overrideAttrs (oldAttrs: rec {
  #   version = "main";
  #   src = pkgs.fetchFromGitHub {
  #     owner = "aome510";
  #     repo = "spotify-player";
  #     rev = "master";
  #     hash = "sha256-yjm5NFW+6vEyv45AVfwx+6w2dJ3lKj/UM2NQhGW5SSs=";
  #   };
  #   cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
  #     inherit src;
  #     name = "spotify-player-main";
  #     hash = "sha256-rqDLkzCl7gn3s/37MPytYaGb0tdtemYi8bgEkrkllDU=";
  #   };
  # });
in
{
  options.agindin.spotify = {
    enable = mkEnableOption "spotify-player";
  };
  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.spotify-player = {
      enable = true;
      # package = spotify-player-main;
    };
  };
}

