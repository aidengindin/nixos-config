{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
    home.file."config/nvim/lua" = {
      "init.lua".source = ./nvim/init.lua;
      "plugins.lua".source = ./nvim/plugins.lua;
    };
  };
}

