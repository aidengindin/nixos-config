{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin.programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
}

