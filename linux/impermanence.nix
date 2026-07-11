{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.impermanence;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  wipeScript = ''
    mkdir -p /mnt
    ${
      if cfg.useLuks then
        "mount -o subvol=/ /dev/mapper/cryptroot /mnt"
      else
        "mount -o subvol=/ /dev/disk/by-label/${cfg.deviceLabel} /mnt"
    }

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
    ${
      if cfg.wipeHome then
        ''
          if [ -e /mnt/home ]; then
            btrfs subvolume delete --commit-after /mnt/home
          fi
        ''
      else
        ""
    }

    # Create empty subvolumes
    btrfs subvolume create /mnt/root
    ${
      if cfg.wipeHome then
        ''
          btrfs subvolume create /mnt/home
        ''
      else
        ""
    }

    umount /mnt
  '';
in
{
  options.agindin.impermanence = {
    enable = mkEnableOption ''
      Whether to enable impermanence.

      This should ONLY be enabled if configured at install time.
      DO NOT try to enable it later!!!
    '';

    fileSystem = mkOption {
      type = types.enum [ "btrfs" ];
      description = "Filesystem to use for impermanence.";
    };

    useLuks = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the root filesystem uses LUKS encryption. Affects how the wipe script mounts the device.";
    };

    deviceLabel = mkOption {
      type = types.str;
      default = "main-pool";
      description = "Disk label to mount for wiping (for non-LUKS btrfs)";
    };

    wipeHome = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to wipe the /home subvolume on boot.";
    };

    persistentSubvolumes = mkOption {
      type = types.listOf types.str;
      default = [
        "persist"
        "nix"
      ];
      description = "btrfs subvolumes to persist.";
    };

    systemDirectories = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "System directories to persist";
    };
    systemFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "System files to persist";
    };
    userDirectories = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "User directories to persist (relative to `/home/agindin`)";
    };
    userFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "User files to persist (relative to `/home/agindin`)";
    };
    ephemeralUserDirectories = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        User directories (relative to `/home/agindin`) that should always exist
        but whose contents are NOT persisted. Recreated empty on every boot —
        useful as scratch space for temporary downloads.
      '';
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
        after = [
          "local-fs.target"
          "fix-home-permissions.service"
        ];
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
      users.agindin = mkIf cfg.wipeHome {
        directories = cfg.userDirectories ++ [
          "Music"
          "Pictures"
          "Documents"
          "Videos"
          "cad"
          "code"
          ".cache/nix"
          {
            directory = ".ssh";
            mode = "0700";
          }
          {
            directory = ".gnupg";
            mode = "0700";
          }
        ];
        files = cfg.userFiles;
      };
    };

    # Recreate ephemeral scratch dirs (e.g. Downloads) empty on every boot. They
    # aren't persisted, so their contents are wiped with the root/home subvolume;
    # this just guarantees the directory itself exists as a landing spot.
    systemd.tmpfiles.rules = map (
      dir: "d /home/agindin/${dir} 0755 agindin users -"
    ) cfg.ephemeralUserDirectories;

    # For traditional (non-systemd) initrd
    boot.initrd.postDeviceCommands = mkIf (!config.boot.initrd.systemd.enable) wipeScript;

    # For systemd stage 1 initrd (e.g. when jovian-nixos enables it)
    boot.initrd.systemd.services.wipe-root = mkIf config.boot.initrd.systemd.enable {
      description = "Wipe BTRFS root subvolume";
      wantedBy = [ "initrd.target" ];
      # DefaultDependencies=no strips systemd's implicit ordering, so we must
      # explicitly wait for LUKS decryption; otherwise the script races the
      # cryptsetup unit and tries to mount /dev/mapper/cryptroot before it exists.
      after = lib.optionals cfg.useLuks [ "systemd-cryptsetup@cryptroot.service" ];
      requires = lib.optionals cfg.useLuks [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = wipeScript;
    };

    age.identityPaths = [
      "/persist/etc/ssh/ssh_host_ed25519_key"
      "/persist/home/agindin/.ssh/id_ed25519"
    ];
  };
}
