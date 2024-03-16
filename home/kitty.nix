{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption mkForce mkOverride;
in
{
  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      kitty
    ];
    home-manager.users.agindin.home.file.".config/kitty/kitty.conf".source = ./kitty/kitty.conf;
  };
}

