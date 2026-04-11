{ ... }:
{
  imports = [
    ../../linux/hardening.nix
    ./hardware.nix
    ./home.nix
    ./services.nix
    ./system.nix
  ];
}
