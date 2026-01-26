{ config, lib, ... }:
let
  inherit (lib) mkIf mkMerge;
in
{
  config = mkMerge [
    (mkIf (builtins.elem "thunderbolt" config.boot.initrd.availableKernelModules) {
      services.hardware.bolt.enable = true;
    })
    {
      agindin.impermanence.systemDirectories = mkIf config.agindin.impermanence.enable [
        "/var/lib/boltd"
      ];
    }
  ];
}
