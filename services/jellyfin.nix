{ config, lib, ... }:
let
  cfg = config.agindin.services.jellyfin;
  inherit (lib) mkEnableOption mkIf;
in {
  options.agindin.services.jellyfin = {
    enable = mkEnableOption "Whether to enable Jellyfin.";
  };

  config = mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      config.services.jellyfin.dataDir
    ];
    
    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      config.services.jellyfin.dataDir
    ];
  };
}

