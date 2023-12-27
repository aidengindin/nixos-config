{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin.programs = {
      eza = {
        enable = true;
        git = true;
        icons = true;
      };

      bottom = {
        enable = true;
      };

      zoxide = {
        enable = true;
      };
    };

    environment.systemPackages = with pkgs; [
      bat
      duf
      du-dust
      fd
      fzf
      ldns
      procs
      ripgrep
      sd
    ];
  };
}
