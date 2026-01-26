{
  config,
  lib,
  pkgs,
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
    environment.systemPackages = [ unstablePkgs.opencode ];

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".config/opencode"
      ".local/share/opencode"
      ".local/state/opencode"
    ];
  };
}
