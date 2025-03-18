{ config, lib, pkgs, ... }:
{
  config.homebrew.casks = [
    {
      name = "librewolf";
      args = [
        "--no-quarantine"
      ];
    }
  ];
}
