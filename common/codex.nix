{
  config,
  lib,
  unstablePkgs,
  ...
}:
let
  cfg = config.agindin.codex;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.codex.enable = mkEnableOption "codex";

  config = mkIf cfg.enable {
    environment.systemPackages = [ unstablePkgs.codex ];

    agindin.impermanence.userDirectories = mkIf config.agindin.impermanence.enable [
      ".codex"
    ];
  };
}
