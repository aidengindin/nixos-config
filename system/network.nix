{ config, pkgs, lib, ... }:
{
  config = {
    networking.networkmanager.enable = true;
    services.tailscale.enable = true;
    systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  };
}

