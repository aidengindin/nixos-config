{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agindin.services.calibre-news;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    mapAttrs'
    nameValuePair
    ;

  recipeType = types.submodule (
    { name, ... }:
    {
      options = {
        recipe = mkOption {
          type = types.path;
          description = ''
            Path to the calibre news recipe (a `.recipe` file) passed to
            `ebook-convert`. Note that some recipes (e.g. The Economist) must be
            patched to work in a headless environment.
          '';
        };

        schedule = mkOption {
          type = types.str;
          example = "Sat *-*-* 06:00:00";
          description = "systemd `OnCalendar` expression controlling when this recipe is built.";
        };

        persistent = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether the timer is `Persistent`, i.e. a run missed while the machine
            was off is triggered immediately on next boot.
          '';
        };

        outputProfile = mkOption {
          type = types.str;
          default = "tablet";
          description = "Value passed to `ebook-convert --output-profile`.";
        };

        outputDir = mkOption {
          type = types.str;
          description = ''
            Directory the generated epub is placed in. The file is written under a
            hidden temporary name and atomically renamed into place, so a directory
            watcher (e.g. calibre-web ingestion) never sees a partial file.
          '';
        };

        outputName = mkOption {
          type = types.str;
          default = name;
          description = ''
            Basename (without extension or date) of the generated epub. The build
            date is appended, yielding e.g. `economist-2026-07-04.epub`.
          '';
        };

        timeout = mkOption {
          type = types.str;
          default = "30min";
          description = "systemd `TimeoutStartSec` for the conversion (recipes can take several minutes).";
        };

        cleanup = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to prune old issues after a successful build.";
          };

          directory = mkOption {
            type = types.str;
            description = ''
              Directory to prune (may differ from `outputDir`, e.g. a calibre
              library the epub is imported into).
            '';
          };

          pattern = mkOption {
            type = types.str;
            default = "*";
            description = "`find -name` glob selecting the issue entries (files or directories) to consider.";
          };

          keep = mkOption {
            type = types.ints.positive;
            description = "Number of newest matching entries to keep; older ones are removed.";
          };
        };
      };
    }
  );

  mkService = name: recipe: {
    description = "Build the ${name} news epub with calibre";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # curl is required by recipes whose network transport is patched to use it.
    path = [
      cfg.package
      pkgs.curl
      pkgs.coreutils
      pkgs.findutils
    ];
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      SupplementaryGroups = [ cfg.group ];
      TimeoutStartSec = recipe.timeout;
      # calibre needs a writable HOME for its config/cache; keep it ephemeral.
      RuntimeDirectory = "calibre-news-${name}";
      WorkingDirectory = "/run/calibre-news-${name}";
      Environment = [ "HOME=/run/calibre-news-${name}" ];
      # Re-assert group-write on the output dir immediately before each run, as
      # root (the `+` prefix). The runner writes there as a member of `group`,
      # but a co-owning service may reset the dir's mode between runs — e.g.
      # calibre-web-automated chmods its ingest dir back to 0755 on container
      # start. Doing this per-run (not just at boot) makes the build robust to
      # that regardless of when it last happened.
      ExecStartPre = "+${pkgs.writeShellScript "calibre-news-${name}-ensure-writable" ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg recipe.outputDir}
        ${pkgs.coreutils}/bin/chgrp ${lib.escapeShellArg cfg.group} ${lib.escapeShellArg recipe.outputDir}
        ${pkgs.coreutils}/bin/chmod 2775 ${lib.escapeShellArg recipe.outputDir}
      ''}";
    };

    script = ''
      set -euo pipefail
      umask 022

      out_dir=${lib.escapeShellArg recipe.outputDir}
      base=${lib.escapeShellArg recipe.outputName}
      stamp="$(date +%Y-%m-%d)"
      final="$out_dir/$base-$stamp.epub"
      # Hidden dotfile so a directory watcher (calibre-web ingest) ignores it
      # until the atomic rename, but keep the .epub extension so ebook-convert
      # infers the output format.
      tmp="$out_dir/.$base-$stamp.epub"

      rm -f "$tmp"
      ebook-convert ${recipe.recipe} "$tmp" --output-profile=${lib.escapeShellArg recipe.outputProfile}
      mv -f "$tmp" "$final"
      echo "Wrote $final"
    ''
    + lib.optionalString recipe.cleanup.enable ''

      # Keep only the newest ${toString recipe.cleanup.keep} matching entries.
      clean_dir=${lib.escapeShellArg recipe.cleanup.directory}
      if [ -d "$clean_dir" ]; then
        find "$clean_dir" -mindepth 1 -maxdepth 1 -name ${lib.escapeShellArg recipe.cleanup.pattern} -printf '%T@ %p\n' \
          | sort -rn \
          | tail -n +${toString (recipe.cleanup.keep + 1)} \
          | cut -d' ' -f2- \
          | while IFS= read -r path; do
              echo "Pruning old issue: $path"
              rm -rf -- "$path"
            done
      fi
    '';
  };

  mkTimer = name: recipe: {
    description = "Schedule the ${name} news epub build";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = recipe.schedule;
      Persistent = recipe.persistent;
    };
  };
in
{
  options.agindin.services.calibre-news = {
    enable = mkEnableOption "scheduled calibre news recipe builds";

    package = mkOption {
      type = types.package;
      default = pkgs.calibre;
      defaultText = lib.literalExpression "pkgs.calibre";
      description = "The calibre package providing `ebook-convert`.";
    };

    user = mkOption {
      type = types.str;
      default = "calibre-news";
      description = "Dedicated system user the builds run as.";
    };

    createUser = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to create `user` (a system user) and its primary group. Set to
        false to run as a pre-existing user you manage elsewhere, in which case
        that user must already belong to `group`.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = ''
        Supplementary group the runner joins to gain read/write access to the
        output and cleanup directories.
      '';
    };

    recipes = mkOption {
      type = types.attrsOf recipeType;
      default = { };
      description = "News recipes to build, each with its own schedule and cleanup settings.";
    };
  };

  config = mkIf (cfg.enable && cfg.recipes != { }) {
    users.users = mkIf cfg.createUser {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.user;
        extraGroups = [ cfg.group ];
        description = "calibre-news recipe builder";
      };
    };
    users.groups = mkIf cfg.createUser {
      ${cfg.user} = { };
    };

    systemd.services = mapAttrs' (name: recipe: nameValuePair "calibre-news-${name}" (mkService name recipe)) cfg.recipes;
    systemd.timers = mapAttrs' (name: recipe: nameValuePair "calibre-news-${name}" (mkTimer name recipe)) cfg.recipes;
  };
}
