{ config, lib, pkgs, ... }:
{
  imports = [
    ../../home
  ];

  environment.systemPackage = with pkgs; [
    thefuck
  ];
}
