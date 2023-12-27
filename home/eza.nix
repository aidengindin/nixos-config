{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin.programs.eza = {
    enable = true;
    git = true;
    icons = true;
  };
}
