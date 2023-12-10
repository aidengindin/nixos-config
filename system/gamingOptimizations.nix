{ config, pkgs, lib, ... }:

let
  cfg = config.agindin.gamingOptimizations;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.gamingOptimizations = {
    enable = mkEnableOption "gamingOptimizations";
  };

  services.power-profiles-daemon.enable = false;
  config = mkIf cfg.enable {
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_BAT="performance";
        CPU_SCALING_GOVERNOR_ON_AC="performance";
      };
    };

    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
      ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
    '';
  };
}
