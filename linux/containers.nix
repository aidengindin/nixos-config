{ ... }:

{
  config = {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.containers.enable = true;
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
  };
}
