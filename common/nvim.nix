{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        
        # Move config from home.file to neovim module to avoid conflicts
        extraLuaConfig = builtins.readFile ./nvim/init.lua;
      };
      
      # Use xdg.configFile instead of home.file to manage neovim config files
      xdg.configFile = {
        "nvim/lua/plugins.lua".source = ./nvim/plugins.lua;
        "nvim/lua/keybindings.lua".source = ./nvim/keybindings.lua;
      };
    };

    environment.systemPackages = with pkgs; [
      fzf
      tree-sitter
      gcc
      python313
      lua51Packages.lua
      lua51Packages.luarocks
      lazygit
      
      # LSPs
      lua-language-server
      pyright
      rust-analyzer
      nixd
      nixfmt
      bash-language-server
      haskell-language-server
    ];
  };
}

