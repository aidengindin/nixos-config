{ config, lib, pkgs, ... }:
{
  config.homebrew.casks = [
    {
      name = "librewolf";
      args = {
        no_quarantine = true;
      };
    }
  ];
}
