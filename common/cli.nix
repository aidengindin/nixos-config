{ config, lib, pkgs, ... }:
{
  config = {
    home-manager.users.agindin.programs = {
      eza = {
        enable = true;
        git = true;
        icons = "auto";
      };

      bottom = {
        enable = true;
      };
    };

    environment.systemPackages = with pkgs; [
      bat
      duf
      dust
      fd
      fselect
      fzf
      ldns
      lsof
      procs
      ripgrep
      ripgrep-all
      sd
      usbutils
    ];
  };
}
