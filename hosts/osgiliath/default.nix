{ ... }:
{
  imports = [
    ../../linux/hardening.nix
    ./disko.nix
    ./hardware.nix
    ./home.nix
    ./services.nix
    ./system.nix
  ];
}
