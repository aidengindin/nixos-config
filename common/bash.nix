{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

{
  config = {
    environment.systemPackages = with unstablePkgs; [ atuin ];
    environment.shells = with pkgs; [ bash ];

    programs.bash.blesh.enable = true;

    programs.bash = {
      interactiveShellInit = lib.mkAfter ''
        set -o vi

        # eval "$(${pkgs.starship}/bin/starship init bash)"
        eval "$(${pkgs.atuin}/bin/atuin init bash)"

        # Bindings that don't depend on atuin - run immediately
        if [[ ''${BLE_VERSION-} ]]; then
          ble-bind -m vi_nmap -f 'j' 'backward-char'
          ble-bind -m vi_nmap -f ';' 'forward-char'

          # Change cursor shape based on vi mode
          ble-bind -m vi_nmap --cursor 2
          ble-bind -m vi_imap --cursor 6
          ble-bind -m vi_omap --cursor 2
          ble-bind -m vi_xmap --cursor 2
          ble-bind -m vi_smap --cursor 4
          ble-bind -m vi_cmap --cursor 2

          ble-import -f integration/zoxide
        fi

        # Atuin-dependent binding - defer if ble.sh not yet attached
        __my_atuin_keybind() {
          ble-bind -m vi_nmap -f 'l' '__atuin_history --shell-up-key-binding --keymap-mode=vim-normal'
        }
        if [[ ''${BLE_ATTACHED-} ]]; then
          __my_atuin_keybind
        else
          BLE_ONLOAD+=(__my_atuin_keybind)
        fi
        bind 'set completion-ignore-case on'

        # TODO: TEMPORARY FIX - Remove when nix completion scripts are fixed
        # Override nix completions with dummy functions to prevent arithmetic expansion errors
        # The flake update introduced buggy nix completion scripts causing bash arithmetic expansion errors
        # when typing longer nixos-rebuild commands. Remove these lines and test periodically.
        _dummy_complete() { return 0; }
        complete -F _dummy_complete nix
        complete -F _dummy_complete nix-build  
        complete -F _dummy_complete nixos-rebuild

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

      ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions --icons=auto";
      l = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions --icons=auto";
      ll = "eza -lah --group-directories-first --icons=auto";

      cat = "bat";

      v = "nvim";
      vim = "nvim";
    };

    agindin.impermanence.userDirectories = lib.mkIf config.agindin.impermanence.enable [
      ".local/share/atuin"
    ];
  };
}
