{ config, pkgs, lib, ... }:
{
  config = {
    systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  };
}

