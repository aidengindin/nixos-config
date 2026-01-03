{ lib, pkgs, ... }:

{
  imports = [
    ../../linux
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_jovian;

  networking.hostName = "weathertop";

  zramSwap.enable = true;

  agindin.impermanence = {
    enable = true;
    fileSystem = "btrfs";
    useLuks = false;
    deviceLabel = "main-pool";
  };

  agindin.steam = {
    enable = true;
    deck.enable = true;
  };

  agindin.gamingOptimizations = {
    enable = true;
    amd.enable = true;
  };

  agindin.firefox.enable = true;
  agindin.bluetooth.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
