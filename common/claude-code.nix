{
  config,
  lib,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.claude-code;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.claude-code.enable = mkEnableOption "claude-code";

  config = mkIf cfg.enable {
    environment.systemPackages = [ unstablePkgs.claude-code ];

    agindin.impermanence = mkIf config.agindin.impermanence.enable {
      userDirectories = [
        ".config/claude-code"
        ".local/share/claude-code"
        ".local/state/claude-code"
        ".claude"
      ];
      userFiles = [ ".claude.json" ];
    };
  };
}
