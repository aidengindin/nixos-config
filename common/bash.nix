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
      '';
    };

    # allow home manager to manage bash
    home-manager.users.agindin = {
      programs.bash.enable = true;
    };

    environment.shellAliases = {
      mkdir = "mkdir -p";
      
      ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      l = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      ll = "eza -lah --group-directories-first";

      cat = "bat";
    };
  };
}
