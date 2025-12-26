{ globalVars, ... }:

{
  imports =
    [
      ../../linux
    ];

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      globalVars.keys.khazad-dumUser
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "osgiliath";

  agindin.impermanence = {
    enable = true;
  };

  systemd.timers.bcachefs-fsck = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "quarterly";
      Persistent = true;
    };
  };
  systemd.services.bcachefs-fsck = {
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      bcachefs fsck -n /
    '';
  };

  system.stateVersion = "25.11";
}
