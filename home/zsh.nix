{ config, pkgs, ... }:

{
  config.home-manager.users.agindin.programs.zsh = {
    enable = true;

    enableAutosuggestions = true;
    enableCompletion = true;
    # add `environment.pathsToLink = [ "/share/zsh" ];` to system config to get completions for system packages

    shellAliases = {
      grep = "grep --color=auto";
      ll = "ls -lah";
      mkdir = "mkdir -p";
      ps = "ps aux | grep -v grep --color=auto | grep -i";
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.fetchFromGitHub {
          owner = "romkatv";
          repo = "powerlevel10k";
          rev = "v1.19.0";
          sha256 = "1e063f8c29f8c9914c3c6ec6b4ceb6e27fdb42d172ed54d4bda5aeec9df926de";
        };
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "cabal"
        "command-not-found"
        "docker"
        "docker-compose"
        "docker-machine"
        "git"
        "pip"
      ];
      theme = "powerlevel10k";
    };

    syntaxHighlighting.enable = true;

    initExtra = ''
      setopt GLOB_SUBST

      # Allow binding a key to edit current command in $EDITOR
      autoload -U edit-command-line

      # Fix zsh-autocomplete on NixOS
      bindkey "''${key[Up]}" up-line-or-search

      # Powerlevel10k setup
      POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs virtualenv)
      POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status background_jobs)
      POWERLEVEL9K_PROMPT_ON_NEWLINE=false

      # Status segment customization
      POWERLEVEL9K_STATUS_OK=false
      POWERLEVEL9K_STATUS_HIDE_SIGNAME=true

      # Dir customization
      POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
      POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"
    '';
  };
}
