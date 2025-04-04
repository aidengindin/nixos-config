{ config, lib, pkgs, ... }:
{
  config = {
    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "zap";
        upgrade = true;
      };
      casks = [
        "sol"
        "unnaturalscrollwheels"
      ];
      brews = [
        "qmk"
      ];
    };
  };
}
