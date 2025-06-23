{ config, pkgs, unstablePkgs, ... }:
let
  accentColor = "blue";
in
{
  imports =
    [
      ../../linux
    ];

  boot.kernelPackages = unstablePkgs.linuxPackages_6_15;

  hardware.graphics.package = unstablePkgs.mesa;
  
  environment.systemPackages = with unstablePkgs; [
    libinput
  ];

  # Do not allow external SSH access
  agindin.ssh = {
    enable = false;
  };

  agindin.desktop.enable = true;
  agindin.bluetooth.enable = true;
  agindin.fingerprint.enable = true;

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

