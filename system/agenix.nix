{ config, pkgs, inputs, ... }:
{
  config.environment.systemPackages = with pkgs; [
    inputs.agenix.packages."${system}".default
  ];
}

