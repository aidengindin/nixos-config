{ config, lib, pkgs, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [ bitwarden-cli ];
  };
}

