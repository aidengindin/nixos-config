{
  config,
  lib,
  globalVars,
  ...
}:
let
  cfg = config.agindin.services.tandoor;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.agindin.services.tandoor = {
    enable = mkEnableOption "tandoor";
    domain = mkOption {
      type = types.str;
      default = "tandoor.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      tandoor-secret-key.file = ../secrets/tandoor-secret-key.age;
    };

    services.tandoor-recipes = {
      enable = true;
      port = globalVars.ports.tandoor;
      database.createLocally = true;
      extraConfig = {
        REMOTE_USER_AUTH = "0";
        SECRET_KEY_FILE = config.age.secrets.tandoor-secret-key.path;
      };
    };

    agindin.services.postgres.enable = true;

    agindin.services.caddy.proxyHosts = mkIf config.agindin.services.caddy.enable [
      {
        domain = cfg.domain;
        port = globalVars.ports.tandoor;
      }
    ];
  };
}
