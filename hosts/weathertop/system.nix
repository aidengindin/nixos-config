{ config, pkgs, ... }:

{
  imports = [
    ../../system
  ];

  # need to check if this is correct
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "weathertop";

  boot.kernel.sysctl = {
    "vm.max_map_count" = 262144; 
  };

  jovian = {
    devices.steamdeck = {
      enable = true;
      autoUpdate = true;
      enableGyroDsuService = true;
    };
    steam = {
      enable = true;
      user = "agindin";
      autoStart = true;
      desktopSession = "gnome";
    };
    decky-loader = {
      enable = true;
      user = "agindin";
    };
  };

  environment.systemPackages = [
    pkgs.yuzu-mainline
  ]

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
