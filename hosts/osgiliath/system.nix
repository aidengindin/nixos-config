{ globalVars, ... }:

{
  imports = [
    ../../linux
  ];

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      globalVars.keys.khazad-dumUser
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "osgiliath";

  agindin.impermanence = {
    enable = true;
    fileSystem = "btrfs";
    useLuks = false;
    deviceLabel = "ssd-pool";
    persistentSubvolumes = [
      "persist"
      "nix"
    ];
  };

  # Periodic btrfs scrub for data integrity
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [
      "/"
      "/media"
    ];
  };

  system.stateVersion = "25.11";
}
