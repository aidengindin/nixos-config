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
  workDir = "${cfg.stateDir}/work";

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
        Holds the Adobe device activation (account/), ACSM files being worked on
        (work/), and ones that failed to fulfill (failed/). The activation is
        what a DeACSM install kept under the Calibre plugin config dir; losing
        it means burning another device registration against the Adobe ID, so
        it is backed up.

        A DeACSM activation is *almost* drop-in. For an anonymous account
        DeACSM omits `<adept:username>` entirely (libadobeAccount.py guards it
        with `if account_type != "anonymous"`), while libgourou's parser throws
        "Invalid activation file" when that element is missing. Add it inside
        `<adept:credentials>` to make such an activation usable:

            <adept:username method="anonymous">anonymous</adept:username>

        The text is never read — libgourou hardcodes the username when the
        method is anonymous — only the element and its attribute matter.
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
      "d ${workDir} 0750 acsm ${cfg.group} -"
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

        # tmpfiles rules for a newly persisted directory are applied during
        # activation, before switch-to-configuration starts the impermanence
        # bind mount that then shadows them — so on a switch without a reboot
        # they land on the wrong side of the mount. Create what the run needs
        # rather than trusting them to be there.
        mkdir -p ${workDir} ${failedDir}

        failures=0

        # Never abort the whole run on one book: every mutation is guarded, and
        # the caller invokes this in a `||` context so errexit stays off inside.
        fulfill() {
          claimed="$1"
          name="$(basename "$claimed")"
          echo "Fulfilling $name"

          if ! work="$(mktemp -d)"; then
            echo "Could not create a work directory for $name" >&2
            return 1
          fi

          # acsmdownloader names the output after the book's title and picks
          # the extension (.epub or .pdf) itself, so give it an empty directory
          # and discover what it produced.
          if ! acsmdownloader -D ${accountDir} -O "$work" "$claimed"; then
            echo "Fulfillment failed for $name" >&2
            mv -f "$claimed" ${failedDir}/ || echo "Could not set aside $name" >&2
            rm -rf "$work"
            return 1
          fi

          downloaded=("$work"/*)
          if [ ''${#downloaded[@]} -ne 1 ]; then
            echo "Expected exactly one file from $name, got ''${#downloaded[@]}" >&2
            mv -f "$claimed" ${failedDir}/ || echo "Could not set aside $name" >&2
            rm -rf "$work"
            return 1
          fi

          book="''${downloaded[0]}"
          bookName="$(basename "$book")"

          # adept_remove strips Adobe's ADEPT DRM only. A book carrying some
          # other scheme fails here and is left in failed/ for manual handling.
          if ! adept_remove -D ${accountDir} -o "$work/drm-free-$bookName" "$book"; then
            echo "DRM removal failed for $name" >&2
            mv -f "$claimed" ${failedDir}/ || echo "Could not set aside $name" >&2
            rm -rf "$work"
            return 1
          fi

          # Land in the watched directory atomically, so the importer never
          # sees a partial file.
          if ! cp "$work/drm-free-$bookName" "${cfg.outputDir}/.$bookName.part"; then
            echo "Could not write $bookName to ${cfg.outputDir}" >&2
            mv -f "$claimed" ${failedDir}/ || echo "Could not set aside $name" >&2
            rm -rf "$work"
            return 1
          fi
          if ! mv "${cfg.outputDir}/.$bookName.part" "${cfg.outputDir}/$bookName"; then
            echo "Could not publish $bookName" >&2
            rm -f "${cfg.outputDir}/.$bookName.part"
            mv -f "$claimed" ${failedDir}/ || echo "Could not set aside $name" >&2
            rm -rf "$work"
            return 1
          fi

          echo "Wrote ${cfg.outputDir}/$bookName"
          rm -f "$claimed"
          rm -rf "$work"
        }

        while :; do
          # Claim the inbox before doing any work that can fail. Anything left
          # in the inbox keeps the path unit's glob matching, and a oneshot that
          # exits with the trigger still true is restarted immediately — which
          # is a tight retry loop that burns the start limit and takes the path
          # unit down with it. Draining first makes that impossible.
          for acsm in ${cfg.inboxDir}/*.acsm; do
            if ! mv -f "$acsm" ${workDir}/; then
              echo "Could not claim $acsm out of the inbox; stopping" >&2
              failures=1
              break 2
            fi
          done

          # Also picks up anything a previous run was killed midway through.
          claimed=(${workDir}/*)
          [ ''${#claimed[@]} -eq 0 ] && break

          for book in "''${claimed[@]}"; do
            fulfill "$book" || failures=1
          done
        done

        exit "$failures"
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
