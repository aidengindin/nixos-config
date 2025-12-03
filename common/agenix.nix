{ config, lib, pkgs, agenix, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
