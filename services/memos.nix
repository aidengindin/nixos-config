{ config, lib, pkgs, ... }:
let
  cfg = config.agindin.services.memos;
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
      group = "memos";
    };
    users.groups.memos = {};

    systemd.services.memos = {
    description = "Memos Note-taking Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.memos}/bin/memos --port 5230";
      Restart = "always";
      RestartSec = 5;
      User = "memos";
      StateDirectory = "/var/opt/memos";
      StateDirectoryMode = "0755";
    };

    # preStart = ''
    #   mkdir -p /var/opt/memos
    #   chown memos:memos /var/opt/memos
    # '';
    };
  };
}
