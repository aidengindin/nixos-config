{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.postgres;
  inherit (lib) mkIf mkEnableOption mkOption types;

  mkUserList = users: map (user: { name = user; ensureDBOwnership = true; }) users;

  port = 5432;
in
{
  options.agindin.services.postgres = {
    enable = mkEnableOption "postgres";
    ensureUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of users for which to create Postgres users and associated databases";
    };
  };

  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      ensureUsers = mkUserList cfg.ensureUsers;
      ensureDatabases = cfg.ensureUsers;
      settings.port = port;
    };
  };
}
