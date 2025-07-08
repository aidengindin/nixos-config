{ config, lib, pkgs, unstablePkgs, ... }:
{
  config = {
    environment.systemPackages = with unstablePkgs; [ claude-code ];
  };
}

