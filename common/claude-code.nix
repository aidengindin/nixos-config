{
  config,
  lib,
  pkgs,
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

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/claude-code"
      ".local/share/claude-code"
      ".local/state/claude-code"
    ];
  };
}
