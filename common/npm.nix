{ config, lib, pkgs, ... }:
{
  config.programs.npm = {
    enable = true;
  };
}

