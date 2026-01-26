{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.audiobookshelf;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.audiobookshelf = {
    enable = mkEnableOption "audiobookshelf";
    domain = mkOption {
      type = types.str;
      default = "audiobooks.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      host = "0.0.0.0";
      port = globalVars.ports.audiobookshelf;
      dataDir = "audiobookshelf";
    };

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.audiobookshelf;
      }
    ];

    agindin.services.restic.paths = mkIf config.agindin.services.restic.enable [
      "/var/lib/audiobookshelf"
    ];

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/audiobookshelf"
    ];
  };
}
