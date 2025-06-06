{ config, pkgs, ... }:
{
  environment.persistence."/persist" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/systemd/coredump"
      "/var/lib/nixos"
      "/var/lib/systemd/timers"
      "/var/lib/fprint"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      "/etc/passwd"
      "/etc/group"
      "/etc/shadow"
      "/etc/subuid"
      "/etc/subgid"
      "/etc/adjtime"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
    users.agindin = {
      directories = [
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        "code"
        ".config"
        ".local/share"
        ".local/state"
        ".cache/nix"
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".gnupg"; mode = "0700"; }
      ];
      files = [];
    };
  };

  boot.initrd.postDeviceCommands = ''
    mkdir -p /mnt
    mount -o subvol=/ /dev/mapper/cryptroot /mnt
    if [ -e /mnt/root ]; then
      btrfs subvolume delete /mnt/root
    fi
    if [ -e /mnt/home ]; then
      btrfs subvolume delete /mnt/home
    fi
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    umount /mnt
  '';
}

