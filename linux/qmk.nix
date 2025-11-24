{ config, lib, pkgs, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [ qmk ];
    hardware.keyboard.qmk.enable = true;
  };
}

