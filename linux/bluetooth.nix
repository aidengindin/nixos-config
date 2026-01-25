{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.bluetooth;
  inherit (lib) mkIf mkEnableOption;
in {
  options.agindin.bluetooth = {
    enable = mkEnableOption "Whether to enable bluetooth-related configuration";
  };

  config = mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          # Disable Enhanced Retransmission Mode to fix controller disconnections
          DisablePlugins = "ertm";
        };
      };
    };

    # Disable Bluetooth USB controller autosuspend to prevent disconnections
    services.udev.extraRules = ''
      # Keep Bluetooth controller powered (IMC Networks on Steam Deck)
      ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="13d3", ATTRS{idProduct}=="3553", TEST=="power/control", ATTR{power/control}="on"
    '';

    # System service to ensure Bluetooth stays powered
    systemd.services.bluetooth-keepalive = {
      description = "Keep Bluetooth controller powered";
      after = [ "bluetooth.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo on > /sys/class/bluetooth/hci0/power/control 2>/dev/null || true'";
      };
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/bluetooth/"
    ];
  };
}

