{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.steam;
  inherit (lib) mkIf mkEnableOption;

  gamescopeSteam = pkgs.writeShellApplication {
    name = "gamescope-steam";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      if ! dimensions="$(
        hyprctl -j monitors |
          jq -er '
            (first(.[] | select(.focused)) // first(.[]))
            | [.width, .height]
            | @tsv
          '
      )"; then
        echo "Could not determine the active monitor resolution" >&2
        exit 1
      fi

      read -r width height <<< "$dimensions"

      exec ${config.security.wrapperDir}/gamescope \
        -w "$width" -h "$height" \
        -W "$width" -H "$height" \
        -f -e -- setpriv \
        --inh-caps=-all \
        --ambient-caps=-all \
        -- ${lib.getExe config.programs.steam.package}
    '';
  };

  gamescopeSteamDesktop = pkgs.makeDesktopItem {
    name = "gamescope-steam";
    desktopName = "Steam (Gamescope)";
    comment = "Launch Steam in Gamescope at the active monitor's resolution";
    exec = lib.getExe gamescopeSteam;
    icon = "steam";
    categories = [
      "Game"
      "Network"
    ];
    terminal = false;
  };
in
{
  options.agindin.steam = {
    enable = mkEnableOption "Whether to enable Steam";
    deck.enable = mkEnableOption "Whether to enable options to run on Steam Deck (strict superset of machine.enable)";
    machine.enable = mkEnableOption "Whether to boot into Gamescope interface for a Steam Machine-like experience";
  };

  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };

    programs.gamemode.enable = true;

    programs.gamescope = {
      enable = true;
      package = unstablePkgs.gamescope;
      capSysNice = true;
    };

    environment.systemPackages = [
      gamescopeSteam
      gamescopeSteamDesktop
    ];

    hardware.steam-hardware.enable = true;

    jovian = mkIf (cfg.deck.enable || cfg.machine.enable) {
      devices.steamdeck = mkIf cfg.deck.enable {
        enable = true;
        autoUpdate = true;
        enableGyroDsuService = true;
      };
      steam = {
        enable = true;
        user = "agindin";
        autoStart = true;
        desktopSession = "gnome";
        updater.splash = "jovian";
      };
    };

    agindin.gnome = mkIf (cfg.deck.enable || cfg.machine.enable) {
      enable = true;
      gdm.enable = false;
    };

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/unity3d"
      ".local/share/Steam"
      ".steam"
    ];
  };
}
