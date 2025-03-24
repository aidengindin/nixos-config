{ config, lib, pkgs, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [ nodejs_23 ];
  };
}

