{ config, lib, pkgs, unstablePkgs, ... }:
let
  cfg = config.agindin.services.ollama;
  inherit (lib) mkIf mkEnableOption mkOption types;
in
{
  options.agindin.services.ollama = {
    enable = mkEnableOption "ollama";
    enableRocm = mkOption {
      type = types.bool;
      description = "Whether to enable AMD GPU support";
      default = false;
    };
  };

  config = mkIf cfg.enable {
    users.users.ollama = {
      isSystemUser = true;
      group = "ollama";
      extraGroups = [ "render" "video" ];
      home = "/var/lib/ollama";
      createHome = true;
    };
    users.groups.ollama = {};
    
    services.ollama = {
      enable = true;
      package = unstablePkgs.ollama;
      acceleration = mkIf cfg.enableRocm "rocm";
      rocmOverrideGfx = mkIf cfg.enableRocm "11.0.0";
    };

    # Disable DynamicUser to fix namespace error
    systemd.services.ollama.serviceConfig = {
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "ollama";
      Group = "ollama";
    };

    agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
      "/var/lib/ollama/models"
    ];
  };
}
