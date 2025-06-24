{ config, pkgs, ... }:

{
  imports = [ ../../services ];

  # TODO: this machine should have its own password
  # age.secrets = {
  #   restic-password = {
  #     file = ../../secrets/restic-password.age;
  #     owner = "root";
  #     group = "keys";
  #     mode = "0440";
  #   };
  # };

  agindin.services = {
    # TODO: setup backup
    # restic = {
    #   enable = false;
    #   paths = [
    #   ];
    #   localBackup = {
    #     enable = false;
    #     repository = "/mnt/usbhdd/restic";
    #     repositoryMountUnitName = "mnt-usbhdd.mount";
    #   };
    #   passwordPath = config.age.secrets.restic-password.path;
    # };

    blocky = {
      enable = true;
    };
  };
}
