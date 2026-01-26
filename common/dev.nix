{ pkgs, ... }:
{
  config = {
    programs.java = {
      enable = true;
      package = pkgs.jdk21;
    };

    environment.systemPackages = with pkgs; [
      cargo
      maven
      nodejs_24
    ];
  };
}
