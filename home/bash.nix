{ config, lib, pkgs, ... }:

{
  config = {
    # users.users.agindin.shell = pkgs.bash;
    environment.systemPackages = with pkgs; [ blesh atuin ];
    environment.shells = with pkgs; [ bash ];

    programs.bash = {
      # enable = true;
      interactiveShellInit = lib.mkBefore ''
        source ${pkgs.blesh}/share/blesh/ble.sh
        eval "$(${pkgs.starship}/bin/starship init bash)"
        eval "$(${pkgs.atuin}/bin/atuin init bash)"
      '';
    };

    environment.shellAliases = {
      mkdir = "mkdir -p";
      
      ls = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      l = "eza -la --group-directories-first --no-filesize --no-user --no-time --no-permissions";
      ll = "eza -lah --group-directories-first";

      gg = "git status";
      gc = "git commit -m";
      gca = "git commit -am";
      gp = "git push";
      gpl = "git pull";
      ga = "git add .";

      cat = "bat";
    };
  };
}
