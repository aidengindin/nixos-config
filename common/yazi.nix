{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin = {
    home.file = {
      ".config/yazi/keymap.toml".source = ./yazi/keymap.toml;
    };
    programs.yazi = {
      enable = true;
    };
  };
}
