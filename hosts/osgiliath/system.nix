{ globalVars, ... }:

{
  imports = [
    ../../linux
  ];

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      globalVars.keys.khazad-dumUser
      globalVars.keys.lorienUser
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

  # Media group for shared access to /media
  users.groups.media = {
    gid = 991;
    members = [ "agindin" ];
  };

  # Set permissions on /media filesystem
  systemd.tmpfiles.rules = [
    "d /media 0770 root media -"
  ];

  system.stateVersion = "25.11";
}
