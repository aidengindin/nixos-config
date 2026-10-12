{
  config,
  lib,
  ...
}:
let
  cfg = config.agindin.watchdog;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.agindin.watchdog = {
    enable = mkEnableOption "the Intel chipset (iTCO) hardware watchdog";
  };

  # A hard kernel hang leaves nothing in the journal and the box stays dead
  # until someone power-cycles it (osgiliath froze on 2026-10-10 and sat
  # offline for a day). systemd pets the chipset timer; if PID 1 or the
  # kernel wedges, the pets stop and the board resets itself.
  config = mkIf cfg.enable {
    # intel_oc_wdt and iTCO_wdt both probe on these PCHs, and intel_oc_wdt
    # registers first, so it would take /dev/watchdog0. Blacklisting it leaves
    # iTCO, the long-established driver, as the only device and makes the
    # numbering deterministic.
    boot.blacklistedKernelModules = [ "intel_oc_wdt" ];
    boot.kernelModules = [ "iTCO_wdt" ];

    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      # Also reset if a shutdown or reboot hangs.
      RebootWatchdogSec = "10min";
      WatchdogDevice = "/dev/watchdog0";
    };
  };
}
