# stolen from https://github.com/seanybaggins/nix-home/blob/main/flake.nix

{ config, lib, pkgs, ... }:

{
  config = {
    # Allow the SD card to be discovered from the gamespoce UI
    users.groups.storage = { };
    services.udisks2.enable = true;
    services.udisks2.mountOnMedia = true;
    systemd.services.udiskie = {
      description = "Udiskie Automount Service";
      wantedBy = [ "paths.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.udiskie}/bin/udiskie -2 --no-file-manager --no-notify";
        Restart = "always";
      };
    };
    
    environment.etc."polkit-1/rules.d/50-udiskie.rules".text = ''
      polkit.addRule(function(action, subject) {
        var YES = polkit.Result.YES;
        var permission = {
          // required for udisks1:
          "org.freedesktop.udisks.filesystem-mount": YES,
          "org.freedesktop.udisks.luks-unlock": YES,
          "org.freedesktop.udisks.drive-eject": YES,
          "org.freedesktop.udisks.drive-detach": YES,
          // required for udisks2:
          "org.freedesktop.udisks2.filesystem-mount": YES,
          "org.freedesktop.udisks2.encrypted-unlock": YES,
          "org.freedesktop.udisks2.eject-media": YES,
          "org.freedesktop.udisks2.power-off-drive": YES,
          // required for udisks2 if using udiskie from another seat (e.g. systemd):
          "org.freedesktop.udisks2.filesystem-mount-other-seat": YES,
          "org.freedesktop.udisks2.filesystem-unmount-others": YES,
          "org.freedesktop.udisks2.encrypted-unlock-other-seat": YES,
          "org.freedesktop.udisks2.encrypted-unlock-system": YES,
          "org.freedesktop.udisks2.eject-media-other-seat": YES,
          "org.freedesktop.udisks2.power-off-drive-other-seat": YES
        };
        if (subject.isInGroup("storage")) {
          return permission[action.id];
        }
      });
    '';
  };
}

