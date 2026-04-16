{ pkgs, ... }:
let
  dedrmPlugin = pkgs.fetchurl {
    url = "https://github.com/noDRM/DeDRM_tools/releases/download/v10.0.3/DeDRM_tools_10.0.3.zip";
    sha256 = "8649e30efb0c26e9cca1131df4c9d02d51eccb5028d396cce857f0fa75a62849";
  };

  deacsmPlugin = pkgs.fetchurl {
    url = "https://github.com/Leseratte10/acsm-calibre-plugin/releases/download/v0.0.16/DeACSM_0.0.16.zip";
    sha256 = "0l0bhx8kdvmvfn9z0fpkl488kgf1rcv3vchzgjjwwnwzgfi1pxmm";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "calibre-drm-plugins";
  version = "10.0.3"; # track DeDRM version

  nativeBuildInputs = [ pkgs.unzip ];

  buildCommand = ''
    mkdir -p $out
    ${pkgs.unzip}/bin/unzip ${dedrmPlugin}
    cp DeDRM_plugin.zip $out/
    cp ${deacsmPlugin} $out/DeACSM.zip
  '';
}
