{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    networking.networkmanager.enable = true;
    services.tailscale.enable = true;
    systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;

    # specific to khazad-dum / laptops: disable wifi when wired to prevent arp flux
    networking.networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeText "wifi-wired-exclusive" ''
          interface=$1
          status=$2

          if [[ "$interface" =~ ^en.* ]]; then
            case $status in
              up)
                ${pkgs.networkmanager}/bin/nmcli radio wifi off
                ;;
              down)
                ${pkgs.networkmanager}/bin/nmcli radio wifi on
                ;;
            esac
          fi
        '';
        type = "basic";
      }
    ];

    agindin.impermanence.systemDirectories = lib.mkIf config.agindin.impermanence.enable [
      "/var/lib/tailscale"
      "/etc/NetworkManager/system-connections"
    ];
  };
}
