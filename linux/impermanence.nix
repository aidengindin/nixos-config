{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.impermanence;
  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.agindin.impermanence = {
    enable = mkEnableOption ''
      Whether to enable impermanence.
      
      This should ONLY be enabled if configured at install time.
      DO NOT try to enable it later!!!
    '';

    fileSystem = mkOption {
      type = types.enum [ "btrfs" "bcachefs" ];
      description = "Filesystem to use for impermanence. This determines how impermanence is implemented.";
    };

    systemDirectories = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "System directories to persist";
    };
    systemFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "System files to persist";
    };
    userDirectories = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "User directories to persist (relative to `/home/agindin`)";
    };
    userFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "User files to persist (relative to `/home/agindin`)";
    };
  };

  config = mkIf cfg.enable {

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
      directories = cfg.systemDirectories ++ [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/timers"
        "/var/lib/systemd/catalog"
      ];
      files = cfg.systemFiles ++ [
        "/etc/machine-id"
        "/etc/adjtime"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ]; 
      users.agindin = {
        directories = cfg.userDirectories ++ [
          "Music"
          "Pictures"
          "Documents"
          "Videos"
          "cad"
          "code"
          ".cache/nix"
          { directory = ".ssh"; mode = "0700"; }
          { directory = ".gnupg"; mode = "0700"; }
        ];
        files = cfg.userFiles;
      };
    };
    
    boot.initrd.postDeviceCommands = mkIf (cfg.fileSystem == "btrfs") ''
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
  };
}

