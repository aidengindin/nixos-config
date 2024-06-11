{config, pkgs, ... }:

{
  imports = [ ../../services ];

  agindin.services = {
    ollama.enable = true;
  };
}
