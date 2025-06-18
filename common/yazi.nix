{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin = {
    xdg.configFile = {
      "yazi/keymap.toml".source = ./yazi/keymap.toml;
      "yazi/theme.toml".source = ./yazi/theme.toml;
      "yazi/Catppuccin-mocha.tmTheme".source = ./yazi/Catppuccin-mocha.tmTheme;
    };
    programs.yazi = {
      enable = true;
    };
  };
}
