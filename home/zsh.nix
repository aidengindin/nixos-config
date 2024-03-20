{ config, pkgs, ... }:

{
  config.home-manager.users.agindin.programs.zsh = {
    enable = true;

    enableAutosuggestions = true;
    enableCompletion = true;
    # add `environment.pathsToLink = [ "/share/zsh" ];` to system config to get completions for system packages

    shellAliases = {
      mkdir = "mkdir -p";
      s = "kitten ssh";
      
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

      v = "nvim";
      vi = "nvim";
      vim = "nvim";
    };

    prezto = {
      enable = true;
      terminal.autoTitle = true;
      caseSensitive = false;
    };

    syntaxHighlighting.enable = true;
    
    initExtra = ''
      setopt GLOB_SUBST

      # Allow binding a key to edit current command in $EDITOR
      autoload -U edit-command-line

      # Fix zsh-autocomplete on NixOS
      # bindkey "''${key[Up]}" up-line-or-search

      BAT_THEME="Nord"
    '';
  };
}
