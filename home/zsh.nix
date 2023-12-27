{ config, pkgs, ... }:

{
  config.home-manager.users.agindin.programs = {
    zsh = {
      enable = true;

      enableAutosuggestions = true;
      enableCompletion = true;
      # add `environment.pathsToLink = [ "/share/zsh" ];` to system config to get completions for system packages

      shellAliases = {
        grep = "grep --color=auto";
        mkdir = "mkdir -p";
        ps = "ps aux | grep -v grep --color=auto | grep -i";

        ls = "eza";
        ll = "eza -lah";

        gg = "git status";
        gc = "git commit -m";
        gca = "git commit -am";
        gp = "git push";
        gpl = "git pull";
        ga = "git add .";
      };

      prezto = {
        enable = true;
        # prompt.theme = "powerlevel10k";
        terminal.autoTitle = true;
      };

      syntaxHighlighting.enable = true;
      
      initExtra = ''
        setopt GLOB_SUBST

        # Allow binding a key to edit current command in $EDITOR
        autoload -U edit-command-line

        # Fix zsh-autocomplete on NixOS
        # bindkey "''${key[Up]}" up-line-or-search

        # Powerlevel10k setup
        POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir vcs virtualenv)
        POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs)
        POWERLEVEL9K_PROMPT_ON_NEWLINE=false

        # Status segment customization
        POWERLEVEL9K_STATUS_OK=false
        POWERLEVEL9K_STATUS_HIDE_SIGNAME=true
        POWERLEVEL9K_CONTEXT_FOREGROUND=232
        POWERLEVEL9K_CONTEXT_BACKGROUND=248

        # Dir customization
        POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
        POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"
      '';
    };

    starship = {
      enable = true;
    };
  };
}
