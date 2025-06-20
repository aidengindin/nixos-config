{ config, lib, pkgs, ... }:

{
  config = {
    environment.systemPackages = with pkgs; [ blesh atuin ];
    environment.shells = with pkgs; [ bash ];

    age.secrets = {
      codecompanion-anthropic-key = {
        file = ../secrets/codecompanion-anthropic-key.age;
        owner = "agindin";
        mode = "0400";
      };
      codecompanion-gemini-key = {
        file = ../secrets/codecompanion-gemini-key.age;
        owner = "agindin";
        mode = "0400";
      };
    };

    programs.bash = {
      interactiveShellInit = lib.mkBefore ''
        set -o vi

        source ${pkgs.blesh}/share/blesh/ble.sh

        # Use more ergonomic keys for vi-mode navigation
        ble-bind -m vi_nmap -f 'j' 'backward-char'
        ble-bind -m vi_nmap -f 'l' '__atuin_history --shell-up-key-binding --keymap-mode=vim-normal'
        ble-bind -m vi_nmap -f ';' 'forward-char'

        # Change cursor shape based on vi mode
        ble-bind -m vi_nmap --cursor 2
        ble-bind -m vi_imap --cursor 6
        ble-bind -m vi_omap --cursor 2
        ble-bind -m vi_xmap --cursor 2
        ble-bind -m vi_smap --cursor 4
        ble-bind -m vi_cmap --cursor 2

        ble-import -f integration/zoxide
        eval "$(${pkgs.starship}/bin/starship init bash)"
        eval "$(${pkgs.atuin}/bin/atuin init bash)"
        export ANTHROPIC_API_KEY="$(cat ${config.age.secrets.codecompanion-anthropic-key.path})"
        export GEMINI_API_KEY="$(cat ${config.age.secrets.codecompanion-gemini-key.path})"

        bind -s 'set completion-ignore-case on'

        # Set catppuccin theme for fzf
        export FZF_DEFAULT_OPTS=" \
        --color=bg+:#313244,bg:#1E1E2E,spinner:#F5E0DC,hl:#F38BA8 \
        --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
        --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
        --color=selected-bg:#45475A \
        --color=border:#313244,label:#CDD6F4"
      '';
    };

    # allow home manager to manage bash
    home-manager.users.agindin = {
      programs.bash.enable = true;
      xdg.configFile = {
        "atuin/config.toml".source = ./atuin/config.toml;
        "atuin/themes/catppuccin-mocha-blue.toml".source = ./atuin/themes/catppuccin-mocha-blue.toml;
      };
    };

    environment.shellAliases = {
      mkdir = "mkdir -p";
      
      ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      l = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      ll = "eza -lah --group-directories-first";

      cat = "bat";

      v = "nvim";
      vim = "nvim";
    };
  };
}
