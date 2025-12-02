{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.git = {
        enable = true;
        settings.user = {
          name = "Aiden Gindin";
          email = "aiden@aidengindin.com";
        };
        lfs.enable = true;
      };
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
      };
    };
  };
}
