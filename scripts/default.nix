{ config, lib, pkgs, ... }:
{
  home-manager.users.agindin.home.packages = let
    customScripts = {
      wallabag-video = {
        text = builtins.readFile ./wallabag-video.py;
        interpreter = "${pkgs.python312}/bin/python";
      };
    };

    in
      lib.mapAttrsToList(name: scriptInfo:
        pkgs.writeScriptBin name ''
          #!${scriptInfo.interpreter}
          ${scriptInfo.text}
        ''
      ) customScripts;
}

