{ config, lib, ... }:
{
  config = {
    networking.networkmanager.enable = true;
    services.tailscale.enable = true;
    systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;

    agindin.impermanence.systemDirectories = lib.mkIf config.agindin.impermanence.enable [
      "/var/lib/tailscale"
      "/etc/NetworkManager/system-connections"
    ];
  };
}

