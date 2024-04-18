{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin.programs.java = {
      enable = true;
      package = pkgs.jdk21;
    };
  };
}

