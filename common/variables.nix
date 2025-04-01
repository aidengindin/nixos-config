{ config, lib, pkgs, ... }:
let
  inherit (lib) strings;
in
{
  _module.args = {
    isLinux = strings.hasInfix "linux" pkgs.system;
    isDarwin = strings.hasInfix "darwin" pkgs.system;
  };
}
