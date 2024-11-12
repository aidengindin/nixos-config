{ config, pkgs, ... }:

{
  config = {
    users.users.agindin.shell = pkgs.bash;

    programs.bash = {
      enable = true;
      blesh.enable = true;

      shellAliases = {
        mkdir = "mkdir -p";
        
        ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
        l = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
        ll = "eza -lah --group-directories-first";

        gg = "git status";
        gc = "git commit -m";
        gca = "git commit -am";
        gp = "git push";
        gpl = "git pull";
        ga = "git add .";

        cat = "bat";
      };
    }
  }
}