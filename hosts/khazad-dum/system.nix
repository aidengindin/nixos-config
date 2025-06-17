{ config, pkgs, catppuccin, ... }:
let
  accentColor = "blue";
in
{
  imports =
    [
      ../../linux
    ];

  boot.kernelPackages = pkgs.linuxPackages_6_15;
  boot.kernelParams = [
    "amd_pstate=active"
    "amd_runpm=0"
    "processor.max_cstate=1"
  ];

  # Do not allow external SSH access
  agindin.ssh = {
    enable = false;
  };

  agindin.desktop.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "khazad-dum";

  # Age identity path for agenix
  age.identityPaths = [ "/home/agindin/.ssh/id_ed25519" ];

  boot.kernel.sysctl = {
    "vm.max_map_count" = 262144; 
  };

  services.fwupd.enable = true;
  
  catppuccin = {
    enable = true;
    accent = "blue";
    cache.enable = true;
    sddm = {
      background = "";  # TODO: set a background image
      font = "Noto Sans";
    };
  };

  home-manager.users.agindin.catppuccin = {
    enable = true;
    accent = accentColor;
    cache.enable = true;
    cursors = {
      enable = true;
      accent = accentColor;
    };
    gtk = {
      enable = true;
      accent = accentColor;
      icon.enable = false;
      size = "compact";
    };
    atuin.accent = accentColor;
    fzf.accent = accentColor;
    hyprland.accent = accentColor;
    hyprlock.accent = accentColor;
    mpv.accent = accentColor;
    # wezterm.apply = true;
  };

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

