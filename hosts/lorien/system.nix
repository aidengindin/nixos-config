{ config, pkgs, ... }:

{
  imports =
    [
      ../../system
    ];

  agindin.ssh = {
    enable = true;
    allowedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICEOaGzXodczxTw7jpj/Tt1mQdkqnY5o9Ofh2ghHhOng aiden@thegindins.com"
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "lorien";

  users.users.agindin = {
    isNormalUser = true;
    description = "agindin";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  boot.kernel.sysctl = {
    "vm.max_map_count" = 262144; 
  };

  users.users.agindin.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICEOaGzXodczxTw7jpj/Tt1mQdkqnY5o9Ofh2ghHhOng aiden@thegindins.com"
  ];

  virtualisation.docker.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8123 1883 9001 3000 5580 10400 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
