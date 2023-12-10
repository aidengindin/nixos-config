{ config, pkgs, lib, ... }:

let
  cfg = config.agindin.gamingOptimizations;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.gamingOptimizations = {
    enable = mkEnableOption "gamingOptimizations";
  };

  config = mkIf cfg.enable {

    # Use the performance CPU governor
    services.power-profiles-daemon.enable = false;
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_BAT="performance";
        CPU_SCALING_GOVERNOR_ON_AC="performance";
      };
    };

    # Use the Kyber I/O scheduler
    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
      ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
    '';

    boot.kernel.sysctl = {
      "vm.swappiness" = 1;                # Set swappiness as low as possible
      "vm.compaction_proactiveness" = 0;  # Disable memory compaction
      "vm.page_lock_unfairness" = 1;      # Not really sure what this does tbh, see cryoutilities
    };
  };
}
