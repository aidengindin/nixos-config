{ config, lib, ... }:
let
  cfg = config.agindin.steam;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.steam = {
    enable = mkEnableOption "Whether to enable Steam";
    deck.enable = mkEnableOption "Whether to enable options to run on Steam Deck (strict superset of machine.enable)";
    machine.enable = mkEnableOption "Whether to boot into Gamescope interface for a Steam Machine-like experience";
  };

  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };

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

