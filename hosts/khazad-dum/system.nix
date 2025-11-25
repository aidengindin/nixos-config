{ config, pkgs, unstablePkgs, ... }:
let
  accentColor = "blue";
in
{
  imports =
    [
      ../../linux
    ];

  boot.kernelPackages = pkgs.linuxPackages_6_17;

  hardware.graphics.package = pkgs.mesa;
  
  environment.systemPackages = with pkgs; [
    libinput
  ];

  # Do not allow external SSH access
  agindin.ssh = {
    enable = false;
  };

  agindin.desktop.enable = true;
  agindin.bluetooth.enable = true;
  agindin.fingerprint.enable = true;
  agindin.avahi.enable = true;

  agindin.kanata = {
    enable = true;
    keyboardDevices = [ "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "khazad-dum";

  # Age identity path for agenix
  age.identityPaths = [ "/home/agindin/.ssh/id_ed25519" ];

  boot.kernel.sysctl = {
    "vm.max_map_count" = 262144; 
  };

  zramSwap = {
    enable = true;
  };

  services.fwupd.enable = true;
  
  agindin.zwift.enable = true;

  agindin.steam.enable = true;

  services.udev.extraRules = ''
    # Framework 13 AMD Fingerprint Reader Fix
    # 1. Disable autosuspend (power/control="on") prevents it from turning off while computer is in use.
    # 2. Enable persistence (power/persist="1") helps it survive system suspend.
    # 3. Locks the persist file prevent other processes from overwriting it.
    ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="27c6", ATTRS{idProduct}=="609c", ATTR{power/persist}="1", ATTR{power/control}="on", RUN+="${pkgs.coreutils}/bin/chmod 444 %S%p/../power/persist"

    # If a USB device supports wakeup, enable it automatically.
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
  '';

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 9001 3000 5580 10400 ];
  # networking.firewall.allowedUDPPorts = [ ... ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}

