{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.kitty;
  inherit (lib) mkIf mkEnableOption;
in
{
  imports = [
    ./variables.nix
  ];

  options.agindin.kitty = {
    enable = mkEnableOption "kitty";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.kitty
    ];
    home-manager.users.agindin.home.file.".config/kitty/kitty.conf".source = ./kitty/kitty.conf;
  };
}

