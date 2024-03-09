{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.rustic;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.services.rustic = {
    enable = mkEnableOption "rustic";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ rustic-rs ];
    age.secrets.rustic-password.file = ../secrets/rustic-password.age;
    home-manager.users.agindin.home.file = {
      ".config/rustic/rustic.toml".source = ./rustic.toml;
    };
  };
}

