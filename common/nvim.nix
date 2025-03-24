{ config, lib, pkgs, ... }:
{
  config = {
    age.secrets = {
      codecompanion-anthropic-key.file = ../secrets/codecompanion-anthropic-key.age;
      owner = "agindin";
      mode = "0400";
    };

    home-manager.users.agindin = {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
      };
      home.file = {
        ".config/nvim/init.lua".source = ./nvim/init.lua;
        ".config/nvim/lua/plugins.lua".source = ./nvim/plugins.lua;
        ".config/nvim/lua/keybindings.lua".source = ./nvim/keybindings.lua;
      };
    };

    environment.systemPackages = with pkgs; [
      fzf
    ];
  };
}

