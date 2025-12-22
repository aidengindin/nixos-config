{ pkgs, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      bat
      bottom
      duf
      dust
      eza
      fd
      fselect
      fzf
      jq
      ldns
      lsof
      procs
      ripgrep
      ripgrep-all
      sd
      usbutils
    ];
  };
}
