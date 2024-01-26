{ config, pkgs, agenix, ... }:
{
  config.environment.systemPackages = with pkgs; [
    agenix.packages."${system}".default
  ];
}

