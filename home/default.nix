{ config, ... }:
{
  imports = [
    ./firefox.nix
  ];

  config.home.stateVersion = "23.11";
}
