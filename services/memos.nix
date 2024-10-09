{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.freshrss;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.memos = {
    enable = mkEnableOption "memos";
    host = mkOption {
      type = types.str;
      default = "memos.gindin.xyz";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ memos ];

    users.users.memos = {
      isSystemUser = true;
      description = "Memos Service User";
    };

    systemd.services.memos = {
    description = "Memos Note-taking Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.memos}/bin/memos --port 5230";
      Restart = "always";
      RestartSec = 5;
      User = "memos";
    };

    preStart = ''
      mkdir -p /var/opt/memos
      chown memos:memos /var/lib/memos
    '';
    };
  };
}
