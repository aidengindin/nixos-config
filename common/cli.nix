{ config, lib, pkgs, ai-tools, ... }:
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

    environment.systemPackages = (with pkgs; [
      bat
      duf
      du-dust
      fd
      fselect
      fzf
      ldns
      procs
      ripgrep
      ripgrep-all
      sd
    ]) ++ (with ai-tools.packages.${pkgs.system}; [
      crush
    ]);
  };
}
