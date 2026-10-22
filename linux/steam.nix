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

    # gamescope-steam asks hyprctl for the active monitor's geometry.
    environment.systemPackages = [
      gamescopeSteam
      gamescopeSteamDesktop
    ];

    hardware.steam-hardware.enable = true;

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/unity3d"
      ".local/share/Steam"
      ".steam"
    ];
  };
}
