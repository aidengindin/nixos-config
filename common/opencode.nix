{
  config,
  lib,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.opencode;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.opencode.enable = mkEnableOption "opencode";

  config = mkIf cfg.enable {
    home-manager.users.agindin.programs.opencode = {
      enable = true;
      package = unstablePkgs.opencode;
      skills = ./opencode/skills;
      settings = {
        hooks = {
          Stop = [
            {
              type = "command";
              command = "$XDG_CONFIG_HOME/opencode/skills/taskmaster/hooks/check-completion.sh";
              timeout = "10";
            }
          ];
        };
      };
    };

    home-manager.users.agindin.home.activation.opencodeScriptPermissions =
      lib.hm.dag.entryAfter [ "writeBoundary" ]
        ''
          chmod +x "$XDG_CONFIG_HOME/opencode/skills/taskmaster/hooks/check-completion.sh"
        '';

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/opencode"
      ".local/share/opencode"
      ".local/state/opencode"
    ];
  };
}
