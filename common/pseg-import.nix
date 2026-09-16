{
  config,
  lib,
  pkgs,
  customPkgs,
  globalVars,
  ...
}:
let
  cfg = config.agindin.pseg-import;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    makeBinPath
    ;
in
{
  options.agindin.pseg-import = {
    enable = mkEnableOption "PSEG usage CSV to Home Assistant statistics import";

    package = mkOption {
      type = types.package;
      default = customPkgs.pseg-import;
      description = "Package providing the pseg-import binary.";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "Path to a file containing a Home Assistant long-lived access token.";
    };

    homeAssistantUrl = mkOption {
      type = types.str;
      default = globalVars.homeAssistant.tailscaleUrl;
      description = ''
        Base URL of the Home Assistant instance. Defaults to the Tailscale
        address so imports work away from the house.
      '';
    };

    watchDir = mkOption {
      type = types.str;
      default = "/home/agindin/Downloads";
      description = "Directory watched for new PSEG exports.";
    };

    filePattern = mkOption {
      type = types.str;
      default = "Usage*.csv";
      description = ''
        Glob for candidate exports. Files matching it are still checked against
        the PSEG header before being touched, so unrelated downloads that happen
        to match are left alone.
      '';
    };

    energyStatisticId = mkOption {
      type = types.str;
      default = "sensor:pseg_nj_imported_energy";
      description = "External statistic ID receiving cumulative kWh.";
    };

    costStatisticId = mkOption {
      type = types.str;
      default = "sensor:pseg_nj_imported_cost";
      description = "External statistic ID receiving cumulative USD.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "America/New_York";
      description = ''
        Time zone the export's timestamps are written in. This is the meter's
        zone, not the laptop's: khazad-dum runs automatic-timezoned and forces
        time.timeZone to null, and the readings stay on New Jersey time no
        matter where the machine happens to be.
      '';
    };

    notify = mkOption {
      type = types.bool;
      default = true;
      description = "Send a desktop notification on success and failure.";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.agindin.systemd.user = {
      # Watch the directory rather than PathExistsGlob on the files themselves.
      # A path unit only re-arms once its condition goes false again, so an
      # unrelated Usage*.csv that the importer correctly declines to touch would
      # latch PathExistsGlob permanently and block every later import. Watching
      # the directory costs a few sub-second no-op runs instead.
      paths.pseg-import = {
        Unit.Description = "Watch for a PSEG usage export to import";
        Path = {
          PathChanged = cfg.watchDir;
          Unit = "pseg-import.service";
        };
        Install.WantedBy = [ "default.target" ];
      };

      services.pseg-import = {
        # No network ordering: network-online.target does not exist in the user
        # manager, and a download landing in the watch directory already implies
        # the network was up. An unreachable Home Assistant is handled by the
        # importer instead, which keeps the file and notifies.
        Unit.Description = "Import a PSEG hourly usage export into Home Assistant";
        Service = {
          Type = "oneshot";
          ExecStart = getExe cfg.package;
          Environment = [
            "HA_URL=${cfg.homeAssistantUrl}"
            "HA_TOKEN_FILE=${cfg.tokenFile}"
            "WATCH_DIR=${cfg.watchDir}"
            "FILE_GLOB=${cfg.filePattern}"
            "ENERGY_STATISTIC_ID=${cfg.energyStatisticId}"
            "COST_STATISTIC_ID=${cfg.costStatisticId}"
            "TIMEZONE=${cfg.timeZone}"
            "NOTIFY=${if cfg.notify then "1" else "0"}"
            "PATH=${makeBinPath [ pkgs.libnotify ]}"
            # notify-send needs the session bus, which the user manager does not
            # always have in its own environment. %t is $XDG_RUNTIME_DIR.
            "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus"
          ];
        };
      };
    };
  };
}
