# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/27e0469a-aecb-4676-8d64-1ff5e6d37a5b";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/D8E6-C9CE";
      fsType = "vfat";
    };

    fileSystems."/mnt/usbhdd" =
    { device = "/dev/disk/by-uuid/21ad0ead-db3c-46c0-a6aa-20bd470866e2";
      fsType = "btrfs";
      options = [ "subvol=usbhdd" ];
    };

  # fileSystems."/backup" = {
  #   device = "21ad0ead-db3c-46c0-a6aa-20bd470866e2";
  #   fsType = "btrfs";
  #   options = [ "subvol=@" "compress=zstd" ];
  # };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/9f8149d0-1d98-4dcb-a2d7-453b0e0caae0"; }
    ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp1s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
