{ config, ... }:
{
  imports = [
    ../../common
  ];

  agindin.mcp = {
    enable = true;
    servers = {
      filesystem = {
        enable = true;
        args = [ "/var/lib/hermes/workspace" ];
      };
      git.enable = true;
      fetch.enable = true;
      nixos.enable = true;
      github = {
        enable = true;
        tokenFile = config.age.secrets.hermes-github-token.path;
      };
      liftosaur.enable = true;
      intervals = {
        enable = true;
        envFile = config.age.secrets.hermes-intervals-env.path;
      };
    };
  };

  home-manager.users.agindin.home.stateVersion = "25.11";
}
