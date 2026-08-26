{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.acsm;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  accountDir = "${cfg.stateDir}/account";
  failedDir = "${cfg.stateDir}/failed";

  # libgourou's utils look for device.xml/activation.xml/devicesalt in a few
  # implicit locations; always pass -D so the unit's cwd can never matter.
  # adept_activate is the exception: it *creates* the directory, via -O.
  adeptWrapper = pkgs.writeShellScriptBin "acsm-adept" ''
    if [ $# -lt 1 ]; then
      echo "usage: acsm-adept <acsmdownloader|adept_remove|adept_loan_mgt|adept_activate> [args...]" >&2
      exit 64
    fi
    util="$1"
    shift
    case "$util" in
      adept_activate)
        # adept_activate refuses to write into a directory that already exists,
        # but tmpfiles has already created an empty one.
        rmdir ${accountDir} 2> /dev/null || true
        exec ${pkgs.libgourou}/bin/adept_activate -O ${accountDir} "$@"
        ;;
      acsmdownloader | adept_remove | adept_loan_mgt)
        exec ${pkgs.libgourou}/bin/"$util" -D ${accountDir} "$@"
        ;;
      *)
        echo "acsm-adept: unknown util '$util'" >&2
        exit 64
        ;;
    esac
  '';
in
{
  options.agindin.services.acsm = {
    enable = mkEnableOption "ACSM fulfillment via libgourou";

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/acsm";
      description = ''
        Holds the Adobe device activation (account/) and ACSM files that failed
        to fulfill (failed/). The activation is what a DeACSM install kept under
        the Calibre plugin config dir; losing it means burning another device
        registration against the Adobe ID, so it is backed up.
      '';
    };

    inboxDir = mkOption {
      type = types.str;
      default = "/media/acsm-inbox";
      description = "Drop .acsm files here; a path unit fulfills them.";
    };

    outputDir = mkOption {
      type = types.str;
      default = config.agindin.services.bookorbit.dockPath;
      description = ''
        Where fulfilled, DRM-free books are written. Defaults to BookOrbit's
        Book Dock, which imports whatever lands in it.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = ''
        Primary group of the `acsm` user. Must be a group that can write to
        outputDir, and that the consuming service can read.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.acsm = {
      isSystemUser = true;
      group = cfg.group;
      description = "ACSM fulfillment (libgourou)";
      home = cfg.stateDir;
    };

    environment.systemPackages = [ adeptWrapper ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 acsm ${cfg.group} -"
      # Contains the device private key material.
      "d ${accountDir} 0700 acsm ${cfg.group} -"
      "d ${failedDir} 0750 acsm ${cfg.group} -"
      "d ${cfg.inboxDir} 0775 acsm ${cfg.group} -"
    ];

    systemd.paths.acsm-fulfill = {
      description = "Watch for ACSM files to fulfill";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathExistsGlob = "${cfg.inboxDir}/*.acsm";
        Unit = "acsm-fulfill.service";
      };
    };

    systemd.services.acsm-fulfill = {
      description = "Fulfill ACSM files and strip ADEPT DRM";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.libgourou ];
      serviceConfig = {
        Type = "oneshot";
        User = "acsm";
        Group = cfg.group;
        # Group-writable output so the consuming service can move/delete it.
        UMask = "0002";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          cfg.stateDir
          cfg.inboxDir
          cfg.outputDir
        ];
      };
      script = ''
        set -u
        shopt -s nullglob

        # A path unit does not re-trigger while its service is still running and
        # the glob still matches, so drain the inbox rather than taking one pass:
        # anything dropped mid-run would otherwise sit there unnoticed.
        while true; do
          pending=(${cfg.inboxDir}/*.acsm)
          [ ''${#pending[@]} -eq 0 ] && break

          for acsm in "''${pending[@]}"; do
            echo "Fulfilling $acsm"

            # acsmdownloader names the output after the book's title and picks
            # the extension (.epub or .pdf) itself, so give it an empty directory
            # and discover what it produced.
            work="$(mktemp -d)"

            if ! acsmdownloader -D ${accountDir} -O "$work" "$acsm"; then
              echo "Fulfillment failed for $acsm" >&2
              mv -f "$acsm" ${failedDir}/
              rm -rf "$work"
              continue
            fi

            downloaded=("$work"/*)
            if [ ''${#downloaded[@]} -ne 1 ]; then
              echo "Expected exactly one file from $acsm, got ''${#downloaded[@]}" >&2
              mv -f "$acsm" ${failedDir}/
              rm -rf "$work"
              continue
            fi

            book="''${downloaded[0]}"
            name="$(basename "$book")"

            # adept_remove strips Adobe's ADEPT DRM only. A book carrying some
            # other scheme fails here and is left in failed/ for manual handling.
            if ! adept_remove -D ${accountDir} -o "$work/drm-free-$name" "$book"; then
              echo "DRM removal failed for $acsm" >&2
              mv -f "$acsm" ${failedDir}/
              rm -rf "$work"
              continue
            fi

            # Land in the watched directory atomically, so the importer never
            # sees a partial file.
            cp "$work/drm-free-$name" "${cfg.outputDir}/.$name.part"
            mv "${cfg.outputDir}/.$name.part" "${cfg.outputDir}/$name"

            echo "Wrote ${cfg.outputDir}/$name"
            rm -f "$acsm"
            rm -rf "$work"
          done
        done
      '';
    };

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      accountDir
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      cfg.stateDir
    ];
  };
}
