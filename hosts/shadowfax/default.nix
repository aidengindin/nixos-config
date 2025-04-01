{ pkgs, ... }:
{
  imports = [
    ../../macos
    ../../scripts
    ./home.nix
  ];

  system.stateVersion = 5;
}
