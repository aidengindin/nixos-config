{ config, lib, pkgs, ... }:
{
  config = {
    services.nix-daemon.enable = true;
  };
}
