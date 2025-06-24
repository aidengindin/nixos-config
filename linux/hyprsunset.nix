{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.desktop;
  inherit (lib) mkIf;
in {
  config = mkIf cfg.enable {
    systemd.user.services.hyprsunset-scheduler = {
      description = "Hyprsunset blue light filter schedule";
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "60";
        
        MemoryMax = "100M";
        CPUQuota = "10%";

        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [ "%h/.local/state" ];
        PrivateNetwork = false;

        ExecStart = "${pkgs.writeShellApplication {
          name = "hyprsunset-daemon";
          runtimeInputs = with pkgs; [
            sunwait
            hyprsunset
            hyprland
            curl
            jq
          ];
          text = ''
            LOCATION_CACHE="$HOME/.local/state/hyprsunset-location"
            mkdir -p "$(dirname "$LOCATION_CACHE")"

            get_location() {
              local location
              location=$(curl -s "https://ipinfo.io/json" | jq -r '.loc // empty')
              if [ -n "$location" ]; then
                echo "$location" | tr ',' ' '
                return 0
              fi

              return 1
            }

            update_location() {
              # Check if cache is older than 1 day or doesn't exist
              if [[ ! -f "$LOCATION_CACHE" ]] || [[ $(find "$LOCATION_CACHE" -mtime +1 2>/dev/null) ]]; then
                echo "Updating location..."
                if LOCATION=$(get_location); then
                  read -r LAT_RAW LON_RAW <<< "$LOCATION"

                  # Convert to sunwait format (N/S E/W)
                  if [[ "$LAT_RAW" == -* ]]; then
                    LAT="''${LAT_RAW#-}S"
                  else
                    LAT="''${LAT_RAW}N"
                  fi
                  
                  if [[ "$LON_RAW" == -* ]]; then
                    LON="''${LON_RAW#-}W"
                  else
                    LON="''${LON_RAW}E"
                  fi
                  
                  # Store the converted coordinates
                  echo "$LAT $LON" > "$LOCATION_CACHE"
                  echo "Location updated: $LAT $LON (converted from $LAT_RAW $LON_RAW)"
                else
                  echo "Failed to get location, using cached or default"
                  [[ ! -f "$LOCATION_CACHE" ]] && echo "43.00N 71.46W" > "$LOCATION_CACHE"
                fi
              fi
            }

            while true; do
              update_location
              read -r LAT LON < "$LOCATION_CACHE"
              echo "Using location: $LAT, $LON"

              if hyprctl hyprsunset temperature >/dev/null 2>&1; then
                echo "Hyprsunset is running and responsive"
              else
                if pidof hyprsunset >/dev/null; then
                  echo "Hyprsunset process exists but not responsive, waiting..."
                  sleep 3
                  if ! hyprctl hyprsunset temperature >/dev/null 2>&1; then
                    echo "Still not responsive, restarting..."
                    pkill hyprsunset
                    sleep 2
                    hyprsunset &
                    sleep 3
                  fi
                else
                  echo "Starting hyprsunset..."
                  hyprsunset &
                  sleep 3
                fi
              fi

              CURRENT_TIME=$(date +%H%M)
              SUNSET_TIME=$(sunwait list 1 civil set "$LAT" "$LON" | cut -d ' ' -f1 | tr -d ':')

              if [[ "$SUNSET_TIME" -lt "1900" ]]; then
                ACTIVATION_TIME="$SUNSET_TIME"
              else
                ACTIVATION_TIME="1900"
              fi

              if [[ "$CURRENT_TIME" -lt "1200" ]]; then
                # Before noon - use today's sunrise
                SUNRISE_TIME=$(sunwait list 1 civil rise "$LAT" "$LON" | cut -d ' ' -f1 | tr -d ':')
              else
                # After noon - use tomorrow's sunrise
                SUNRISE_TIME=$(sunwait list 2 civil rise "$LAT" "$LON" | sed -n '2p' | cut -d ' ' -f1 | tr -d ':')
              fi

              CURRENT_TEMP=$(hyprctl hyprsunset temperature 2>/dev/null || echo "6000")

              SHOULD_BE_ACTIVE=false
              echo "Current time: $CURRENT_TIME"
              echo "Activation time: $ACTIVATION_TIME"
              echo "Sunrise time: $SUNRISE_TIME"
              if [[ "$CURRENT_TIME" -ge "$ACTIVATION_TIME" ]] || [[ "$CURRENT_TIME" -lt "$SUNRISE_TIME" ]]; then
                SHOULD_BE_ACTIVE=true
              fi

              if [[ "$SHOULD_BE_ACTIVE" == "true" ]] && [[ "$CURRENT_TEMP" != "2000" ]]; then
                echo "Activating blue light filter at $(date)"
                hyprctl hyprsunset temperature 2000
              elif [[ "$SHOULD_BE_ACTIVE" == "false" ]] && [[ "$CURRENT_TEMP" != "6000" ]]; then
                echo "Deactivating blue light filter at $(date)"
                hyprctl hyprsunset temperature 6000
              fi

            sleep 300
            done
          '';
        }}/bin/hyprsunset-daemon";
      };
    };
  };
}
