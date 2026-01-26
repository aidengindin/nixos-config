{
  lib,
  pkgs,
  globalVars,
  ...
}:

{
  imports = [
    ../../linux
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_jovian;

  networking.hostName = "weathertop";

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      globalVars.keys.khazad-dumUser
      globalVars.keys.lorienUser
    ];
  };

  zramSwap.enable = true;

  agindin.impermanence = {
    enable = true;
    fileSystem = "btrfs";
    useLuks = false;
    deviceLabel = "main-pool";
    userDirectories = [
      "emulation"
      ".config/Ryujinx"
      ".config/steam-rom-manager"
    ];
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

  environment.systemPackages = with pkgs; [
    ryubing
    steam-rom-manager
  ];

  services.udev.packages = with pkgs; [ game-devices-udev-rules ];

  # Fix 8BitDo controller disconnections by disabling USB autosuspend
  services.udev.extraRules = ''
    # 8BitDo controller dongles - disable USB autosuspend
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="2dc8", TEST=="power/control", ATTR{power/control}="on"
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
