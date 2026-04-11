{ ... }:
{
  imports = [
    ../../linux/hardening.nix
    ./disko.nix
    ./hardware.nix
    ./home.nix
    # ./impermanence.nix
    ./services.nix
    ./system.nix
  ];
}
