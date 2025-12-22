{ config, lib, ... }:
{
  config = {
    home-manager.users.agindin = {
      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
      };
    };

    agindin.impermanence.userDirectories = lib.mkIf config.agindin.impermanence.enable [
      ".local/share/zoxide"
    ];
  };
}
