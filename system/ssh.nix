{ config, pkgs, lib, ... }:
let
  cfg = config.agindin.ssh;
  inherit (lib) mkOption mkEnableOption mkIf types;
in
{
  options.agindin.ssh = {
    enable = mkEnableOption "ssh";
    allowedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Keys allowed to authenticate ssh sessions.";
    };
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    users.users.agindin.openssh.authorizedKeys.keys = cfg.allowedKeys;
  };
}

