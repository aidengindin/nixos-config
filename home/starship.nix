{ config, pkgs, ... }:
{
  config.home-manager.users.agindin.programs.starship = {
    enable = true;
    settings = {
      battery.disabled = true;
      git_metrics.disabled = false;
      hostname = {
        ssh_symbol = "⎈ ";
      };
    };
  };
}
