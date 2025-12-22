{ config, lib, ... }:
let
  inherit (lib) mkIf;
in {
  config = mkIf (builtins.elem "thunderbolt" config.boot.initrd.availableKernelModules) {
    services.hardware.bolt.enable = true;
  };
}

