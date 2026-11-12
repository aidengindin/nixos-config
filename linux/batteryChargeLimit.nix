{
  config,
  lib,
  pkgs,
  ...
}:

# Battery charge limit, driven through UPower so the session can lift it
# without sudo (UPower's polkit policy lets the active session call
# EnableChargeThreshold). The limit is the normal state: it is turned on at
# every boot and again whenever the AC adapter goes offline, so a one-off
# "charge to full" before travelling can't be left on by accident. The bar
# toggle lives in linux/hyprland/scripts/battery-status.sh.
let
  cfg = config.agindin.batteryChargeLimit;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  device = "/org/freedesktop/UPower/devices/battery_${cfg.battery}";
in
{
  options.agindin.batteryChargeLimit = {
    enable = mkEnableOption "a battery charge limit that comes back on when unplugged";

    limit = mkOption {
      type = types.ints.between 50 100;
      default = 80;
      description = "Charge percentage at which the battery stops charging.";
    };

    battery = mkOption {
      type = types.str;
      default = "BAT1";
      description = "Kernel name of the battery under /sys/class/power_supply.";
    };

    adapter = mkOption {
      type = types.str;
      default = "ACAD";
      description = "Kernel name of the AC adapter under /sys/class/power_supply.";
    };
  };

  config = mkIf cfg.enable {
    services.upower.enable = true;

    services.udev.extraRules = ''
      # UPower takes its thresholds from this property ("start,end"); its
      # hwdb default is 75,80. Firmware that only has an end threshold
      # ignores the start value.
      SUBSYSTEM=="power_supply", KERNEL=="${cfg.battery}", ENV{CHARGE_LIMIT}="${toString (cfg.limit - 5)},${toString cfg.limit}"

      # Unplugged: put the limit back.
      SUBSYSTEM=="power_supply", KERNEL=="${cfg.adapter}", ACTION=="change", ATTR{online}=="0", RUN+="${config.systemd.package}/bin/systemctl start --no-block battery-charge-limit.service"
    '';

    # UPower keeps the on/off state in /var/lib/upower, which impermanent
    # hosts wipe, and it would otherwise start with the limit off. Turning it
    # on at boot makes the limit the default without persisting anything.
    systemd.services.battery-charge-limit = {
      description = "Turn the battery charge limit back on";
      wantedBy = [ "multi-user.target" ];
      requires = [ "upower.service" ];
      after = [ "upower.service" ];
      path = [
        config.systemd.package
        pkgs.procps
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        # UPower can own its bus name before it has published the battery.
        for _ in $(seq 10); do
          if busctl call org.freedesktop.UPower ${device} \
            org.freedesktop.UPower.Device EnableChargeThreshold b true; then
            # Refresh the bar's battery segment (signal 12) if it is running.
            pkill -RTMIN+12 -x waybar || true
            exit 0
          fi
          sleep 1
        done
        echo "UPower never exposed ${device}" >&2
        exit 1
      '';
    };
  };
}
