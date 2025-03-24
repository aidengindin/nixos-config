{ config, lib, pkgs, agenix, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      agenix.packages.${pkgs.system}.default
    ];
  };
}
