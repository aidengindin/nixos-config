{ config, lib, pkgs, ... }:
let
  inherit (lib) strings;
in
{
  _module.args = {
    isLinux = strings.hasInfix "linux" pkgs.stdenv.hostPlatform.system;
    isDarwin = strings.hasInfix "darwin" pkgs.stdenv.hostPlatform.system;
  };
}
