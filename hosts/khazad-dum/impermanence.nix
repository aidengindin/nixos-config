{ config, lib, pkgs, ... }:
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

    # Ensure Home Manager activates after filesystem mounts
    home-manager-agindin = {
      after = [ "local-fs.target" "fix-home-permissions.service" ];
      wants = [ "fix-home-permissions.service" ];
    };
  };

  environment.persistence."/persist" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/timers"
      "/var/lib/systemd/catalog"
      "/var/lib/nixos"
      "/var/lib/fprint"
      "/var/lib/tailscale"
      "/var/lib/boltd"
      "/var/lib/ollama/models"
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
        "cad"
        "code"
        ".cache/spotify-player"
        ".cache/orca-slicer"
        ".config/Bitwarden"
        ".config/chromium"
        ".config/qt5ct"
        ".config/qt6ct"
        ".config/kdeconnect"
        ".config/unity3d"
        ".config/OrcaSlicer"
        ".config/opencode"
        ".local/share/Anki2"
        ".local/share/atuin"
        ".local/share/flatpak"
        ".local/share/nvim"
        ".local/share/zoxide"
        ".local/share/containers"
        ".local/share/Steam"
        ".local/state/nvim"
        ".local/state/wireplumber"
        ".local/share/opencode"
        ".local/state/opencode"
        ".cache/nix"
        ".mozilla"
        ".claude"
        ".steam"
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".gnupg"; mode = "0700"; }
      ];
      files = [
        ".claude.json"
      ];
    };
  };

  boot.initrd.postDeviceCommands = ''
    mkdir -p /mnt
    mount -o subvol=/ /dev/mapper/cryptroot /mnt

    # Unmount nested subvolumes
    for dir in home nix persist; do
      umount "/mnt/root/$dir" 2>/dev/null || true
    done

    # Delete automatically created nested subvolumes
    for subvol in srv var/lib/portables var/lib/machines tmp var/tmp; do
      btrfs subvolume delete --commit-after "/mnt/root/$subvol" 2>/dev/null || true
    done

    # Delete subvolumes
    if [ -e /mnt/root ]; then
      btrfs subvolume delete --commit-after /mnt/root
    fi
    if [ -e /mnt/home ]; then
      btrfs subvolume delete --commit-after /mnt/home
    fi

    # Create empty subvolumes
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home

    umount /mnt
  '';

  age.identityPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
    "/persist/home/agindin/.ssh/id_ed25519"
  ];
}

