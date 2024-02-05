{ config, pkgs, ... }:

{
  config.home-manager.users.agindin.programs.zsh = {
    enable = true;

    enableAutosuggestions = true;
    enableCompletion = true;
    # add `environment.pathsToLink = [ "/share/zsh" ];` to system config to get completions for system packages

    shellAliases = {
      grep = "grep --color=auto";
      mkdir = "mkdir -p";
      ps = "ps aux | grep -v grep --color=auto | grep -i";
      s = "kitten ssh";
      
      ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
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

      # Powerlevel10k setup, preserved for posterity
      POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs virtualenv)
      POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs)
      POWERLEVEL9K_PROMPT_ON_NEWLINE=false
      POWERLEVEL9K_STATUS_OK=false
      POWERLEVEL9K_STATUS_HIDE_SIGNAME=true
      POWERLEVEL9K_CONTEXT_FOREGROUND=232
      POWERLEVEL9K_CONTEXT_BACKGROUND=248
      POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
      POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"
    '';
  };
}
