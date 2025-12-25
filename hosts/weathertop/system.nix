{ config, lib, pkgs, ... }:

{
  imports = [
    ../../linux
  ];

  # bcachefs was removed from mainline in 6.17, but Jovian's kernel (6.16.x)
  # still has it built-in. Assert on kernel version so we catch this before
  # deploying a broken config when Jovian updates to 6.17+.
  assertions = [{
    assertion = lib.versionOlder config.boot.kernelPackages.kernel.version "6.17";
    message = ''
      Jovian kernel is now ${config.boot.kernelPackages.kernel.version}.
      bcachefs was removed in 6.17 - you need to handle this before deploying!
    '';
  }];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Jovian's kernel (6.16) has bcachefs built-in, override the bcachefs module's
  # attempt to set linuxPackages_latest
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_jovian;

  networking.hostName = "weathertop";

  boot.kernel.sysctl = {
    "vm.max_map_count" = 262144; 
  };

  zramSwap.enable = true;

  agindin.impermanence = {
    enable = true;
    fileSystem = "bcachefs";
    deviceLabel = "main-pool";
  };

  agindin.steam = {
    enable = true;
    deck.enable = true;
  };

  agindin.firefox.enable = true;
  agindin.gamingOptimizations.enable = true;
  agindin.bluetooth.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
