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
        source ${pkgs.blesh}/share/blesh/ble.sh
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
