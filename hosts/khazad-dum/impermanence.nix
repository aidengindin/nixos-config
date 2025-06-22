{ config, pkgs, ... }:
{
  # Fix home directory permissions on boot
  systemd.services = {
    fix-home-permissions = {
      description = "Fix home directory permissions";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "display-manager.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/chown -R agindin:users /home/agindin'";
      };
    };

    # home-manager-activate = {
    #   description = "Set up Home Manager for agindin on boot";
    #   wantedBy = [ "multi-user.target" ];
    #   after = [ "local-fs.target" "persist-home-agindin-.local-state.mount" ];
    #   before = [ "display-manager.service" ];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     User = "agindin";
    #     ExecStart = "${pkgs.bash}/bin/bash -c 'cd /home/agindin && ${config.home-manager.users.agindin.home.activationPackage}/activate'";
    #   };
    # };
  };
  
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
        ".cache"
        ".mozilla"
        ".claude"
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

