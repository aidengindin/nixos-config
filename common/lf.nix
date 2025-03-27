{ config, lib, pkgs, ... }:
{
  config.home-manager.users.agindin = {
    home.file = {
      ".config/lf/icons".source = ./lf/icons.conf;
    };
    programs.lf = {
      enable = true;
      commands = {
        z = ''%{{
          result="$(zoxide query --exclude "$PWD" "$@" | sed 's/\\/\\\\/g;s/"/\\"/g')"
          lf -remote "send $id cd \"$result\""
        }}
        '';

        zi = ''''${{
          result="$(zoxide query -i | sed 's/\\/\\\\/g;s/"/\\"/g')"
          lf -remote "send $id cd \"$result\""
        }}
        '';

        on-cd = ''&{{
          zoxide add "$PWD"
          fmt="$(STARSHIP_SHELL=bash starship prompt | sed 's/\\\[//g;s/\\\]//g' | sed -n 2p)"
          lf -remote "send $id set promptfmt \"$fmt\""
        }}
        '';

        on-select = ''&{{
          lf -remote "send $id set statfmt \"$(eza -ld --color=always "$f" | sed 's/\\/\\\\/g;s/"/\\"/g')\""
        }}
        '';
      };

      settings = {
        # Initial prompt format (placeholder that will be replaced)
        promptfmt = "\\[loading...\\]";

        drawbox = true;
        icons = true;
        info = "size:time";
      };

      extraConfig = ''
        &{{
          sleep 0.1
          lf -remote "send $id on-cd"
        }};
      '';

      keybindings = {
        "h" = null;
        "j" = "updir";
        "k" = "down";
        "l" = "up";
        ";" = "open";

        "x" = "delete";
        "a" = "push %touch<space>";
        "A" = "push %mkdir<space>";
        "om" = "push %chmod<space>";
        "oo" = "push %chown<space>";
        "og" = "push %chgrp<space>";
      };

      previewer = {
        keybinding = "i";
        source = pkgs.writeShellScript "pv.sh" ''
          #!/usr/bin/env bash

          case "$(${pkgs.file}/bin/file --dereference --brief --mime-type "$1")" in
            application/zip) ${pkgs.unzip}/bin/unzip -l "$1";;
            application/x-tar|application/x-gtar) ${pkgs.gnutar}/bin/tar tf "$1";;

            application/pdf) ${pkgs.poppler_utils}/bin/pdftotext -l 10 -nopgbrk -q -- "$1" -;;

            text/*|*/json|*/xml|*/javascript|*/x-shellscript)
              ${pkgs.bat}/bin/bat --color=always --style=numbers,changes --theme="Nord" "$1";;

            image/*)
              # if [[ "$TERM" == "xterm-kitty" ]]; then
              #   ${pkgs.kitty}/bin/kitty +kitten icat \
              #     --clear --transfer-mode=file --place="''${2:-40}x''${3:-30}@0x0" "$1"
              # elif command -v ${pkgs.chafa}/bin/chafa &> /dev/null; then
              #   ${pkgs.chafa}/bin/chafa --fill=space --symbols=block --colors=256 \
              #     --size="''${2:-40}x''${3:-30}" "$1"
              # else
              #   echo "Image file: $(${pkgs.file}/bin/file --dereference --brief "$1")"
              #   echo "Type: $mime_type"
              #   echo "Dimensions: $(${pkgs.imagemagick}/bin/identify \
              #     -format "%wx%h" "$1" 2>/dev/null || echo "unknown")"
              # fi
              echo "File: $(basename "$1")"
              echo "Type: $mime_type"
              # Try to get dimensions with identify if available
              if command -v ${pkgs.imagemagick}/bin/identify &> /dev/null; then
                dimensions=$(${pkgs.imagemagick}/bin/identify -format "%wx%h" "$1" 2>/dev/null)
                if [ $? -eq 0 ]; then
                  echo "Dimensions: $dimensions"
                fi
              fi
              
              # Get file size
              if command -v ${pkgs.coreutils}/bin/stat &> /dev/null; then
                size=$(${pkgs.coreutils}/bin/stat -c %s "$1" 2>/dev/null || 
                       ${pkgs.coreutils}/bin/stat -f %z "$1" 2>/dev/null)
                if [ $? -eq 0 ]; then
                  # Convert to human readable
                  if [ $size -ge 1048576 ]; then
                    echo "Size: $(($size/1048576)) MB"
                  elif [ $size -ge 1024 ]; then
                    echo "Size: $(($size/1024)) KB"
                  else
                    echo "Size: $size bytes"
                  fi
                fi
              fi
              ;;

            *) ${pkgs.file}/bin/file --dereference --brief "$1";;
          esac
        '';
      };
    };
  };
}

