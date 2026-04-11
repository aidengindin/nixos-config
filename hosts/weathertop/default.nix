{ ... }:
{
  imports = [
    ../../linux/hardening.nix
    ./disko.nix
    ./hardware.nix
    ./home.nix
    ./system.nix
  ];
}
