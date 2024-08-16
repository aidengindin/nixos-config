{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.tandoor;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.tandoor = {
    enable = mkEnableOption "tandoor";
    version = mkOption {
      type = types.str;
      example = "1.5.18";
      description = "Tandoor version tag to pull";
    };
    databaseVersion = mkOption {
      type = types.str;
      example = "16.4";
      description = "Postgres container version tag to pull";
    };
  };

  config = mkIf cfg.enable {
    age.secrets = {
      tandoor-secret-key.file = ../secrets/tandoor-secret-key.age;
      tandoor-postgres-password = ../secrets/tandoor-postgres-password.age;
    }

    virtualisation.oci-containers.containers = {
      tandoor = {
        image = "vabene1111/recipes:${cfg.version}";
        environment = {
          TZ = "America/New_York";
        };
      };
    };
  };
}