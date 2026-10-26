{ pkgs, lib, ... }:
{
  imports = [
    ../../linux
  ];

  # Travel laptop: derive the timezone from location via geoclue2 (live).
  # automatic-timezoned requires time.timeZone to be unset, so override the
  # global static value from linux/locale.nix for this host.
  services.automatic-timezoned.enable = true;
  time.timeZone = lib.mkForce null;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "amdgpu.ip_block_mask=0xfffff7ff" # Disable VPE (IP block 11) - workaround for suspend/resume crashes
  ];

  hardware.graphics.package = pkgs.mesa;

  agindin.impermanence = {
    enable = true;
    fileSystem = "btrfs";
    useLuks = true;
    # Downloads is a throwaway landing spot: exists on every boot, contents wiped.
    ephemeralUserDirectories = [ "Downloads" ];
  };

  agindin.ssh = {
    enable = true;
    allowedKeys = [ ];
  };

  agindin.qmk.enable = true;

  agindin.hyprland.enable = true;
  agindin.bluetooth.enable = true;
  agindin.fingerprint.enable = true;
  agindin.avahi.enable = true;

  # Reach the servers' LAN addresses (which blocky hands out for their
  # services) through their Tailscale subnet routes when away from home.
  # Linux clients ignore advertised routes unless told to accept them.
  services.tailscale.extraSetFlags = [ "--accept-routes" ];

  agindin.kanata = {
    enable = true;
    keyboardDevices = [ "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "khazad-dum";

  # Decrypt with the host key only. The user key used to be listed here (and
  # in linux/impermanence.nix), which forced it to stay passphraseless so
  # activation could read it — leaving a root-equivalent key readable by any
  # process running as agindin. mkForce drops the shared module's user key.
  age.identityPaths = lib.mkForce [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  age.secrets.khazad-dum-gh-token = {
    file = ../../secrets/github-token.age;
    owner = "agindin";
  };

  age.secrets.khazad-dum-intervals-env = {
    file = ../../secrets/intervals-env.age;
    owner = "agindin";
  };

  age.secrets.khazad-dum-homeassistant-token = {
    file = ../../secrets/homeassistant-token.age;
    owner = "agindin";
  };

  zramSwap = {
    enable = true;
  };

  services.fwupd.enable = true;

  # External monitor brightness over DDC/CI (e.g. `ddcutil setvcp 10 50`).
  # hardware.i2c loads i2c-dev and grants the i2c group access to /dev/i2c-*.
  hardware.i2c.enable = true;
  users.users.agindin.extraGroups = [ "i2c" ];
  environment.systemPackages = [ pkgs.ddcutil ];

  agindin.steam.enable = true;

  agindin.print3d.enable = true;

  agindin.opencode.enable = true;

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
