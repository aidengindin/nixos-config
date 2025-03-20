{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.git = {
        enable = true;
        userName = "Aiden Gindin";
        userEmail = "aiden@aidengindin.com";
        delta.enable = true;
        lfs.enable = true;
      };
    };
  };
}
