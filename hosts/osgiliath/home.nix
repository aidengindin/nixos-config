{ config, globalVars, ... }:
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
      # Deliberately no github server. The MCP tool surface is curated, but
      # the raw PAT behind it is not, and the agent can read the secret file
      # directly — read_file bypasses the approval layer entirely. Claude
      # Code and Codex keep theirs on khazad-dum, which has its own token.
      liftosaur.enable = true;
      intervals = {
        enable = true;
        envFile = config.age.secrets.hermes-intervals-env.path;
      };

      # Grafana runs on this host, so go straight to the loopback port rather
      # than through Caddy and the OIDC gate.
      grafana = {
        enable = true;
        url = "http://127.0.0.1:${toString globalVars.ports.grafana}";
        tokenFile = config.age.secrets.hermes-grafana-token.path;
      };

      # Home Assistant runs on a separate HAOS box.
      homeAssistant = {
        enable = true;
        url = "http://10.88.88.3:8123";
        tokenFile = config.age.secrets.hermes-homeassistant-token.path;
      };

      time.enable = true;
    };
  };

  home-manager.users.agindin.home.stateVersion = "25.11";
}
