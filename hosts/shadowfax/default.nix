{ pkgs, ... }:
{
  imports = [
    ../../macos
    ./home.nix
  ];

  system.stateVersion = 5;
}
