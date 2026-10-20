{
  config,
  lib,
  ...
}:
let
  cfg = config.agindin.watchdog;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  drivers = [
    "iTCO_wdt"
    "intel_oc_wdt"
  ];
in
{
  options.agindin.watchdog = {
    enable = mkEnableOption "the Intel chipset hardware watchdog";

    driver = mkOption {
      type = types.enum drivers;
      default = "iTCO_wdt";
      description = ''
        Watchdog driver to use. The other one is blacklisted. Both probe on
        recent Intel PCHs, but firmware can leave either one unable to reset
        the board, so pick whichever passes a no-ping test on the host.
      '';
    };
  };

  # A hard kernel hang leaves nothing in the journal and the box stays dead
  # until someone power-cycles it (osgiliath froze on 2026-10-10 and sat
  # offline for a day). systemd pets the chipset timer; if PID 1 or the
  # kernel wedges, the pets stop and the board resets itself.
  config = mkIf cfg.enable {
    # Blacklisting the unused driver leaves exactly one watchdog device, so
    # /dev/watchdog0 is deterministic.
    boot.blacklistedKernelModules = lib.remove cfg.driver drivers;
    boot.kernelModules = [ cfg.driver ];

    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      # Also reset if a shutdown or reboot hangs.
      RebootWatchdogSec = "10min";
      WatchdogDevice = "/dev/watchdog0";
    };
  };
}
