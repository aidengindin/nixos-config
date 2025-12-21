{ config, lib, pkgs, ai-tools, ... }:
let
  cfg = config.agindin.crush;
  inherit (lib) mkEnableOption mkIf;
in {
  options.agindin.crush = {
  enable = mkEnableOption "crush";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with ai-tools.packages.${pkgs.stdenv.hostPlatform.system}; [
      crush
    ];
  };
}

