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

  # Hosts that boot the Jovian Steam session rather than a desktop compositor.
  jovianSession = cfg.deck.enable || cfg.machine.enable;

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

    # Jovian's steam module ships its own Deck-patched gamescope and defines
    # security.wrappers.gamescope itself, so leave it alone on those hosts.
    programs.gamescope = mkIf (!jovianSession) {
      enable = true;
      package = unstablePkgs.gamescope;
      capSysNice = true;
    };

    # gamescope-steam asks hyprctl for the active monitor's geometry, so it only
    # works on desktop hosts; Jovian hosts get Steam from the session itself.
    environment.systemPackages = lib.optionals (!jovianSession) [
      gamescopeSteam
      gamescopeSteamDesktop
    ];

    hardware.steam-hardware.enable = true;

    jovian = mkIf jovianSession {
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

    agindin.gnome = mkIf jovianSession {
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
