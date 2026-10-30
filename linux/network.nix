{
  config,
  lib,
  pkgs,
  globalVars,
  ...
}:
let
  lanIp = globalVars.ips.lan.${config.networking.hostName} or null;
in
{
  config = {
    networking.networkmanager.enable = true;
    services.tailscale.enable = true;
    # blocky answers the servers' Caddy domains with their LAN addresses, so
    # each server advertises its own as a /32 route for clients off the LAN.
    # Traffic to the host's own address is delivered locally, so this needs no
    # IP forwarding. The route still has to be approved in the admin console.
    services.tailscale.extraSetFlags = lib.optional (lanIp != null) "--advertise-routes=${lanIp}/32";
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
