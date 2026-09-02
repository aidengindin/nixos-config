{ pkgs, ... }:
# Claude Desktop, repackaged from Anthropic's official Linux .deb.
#
# The .deb ships a self-contained Electron app: usr/lib/claude-desktop/claude-desktop
# is the vendored Electron ELF (v42.5.1) and usr/bin/claude-desktop is just a symlink
# to it. We patchelf the vendored Electron against nixpkgs libs rather than swapping in
# nixpkgs' electron, because nixpkgs has no electron_42 and the app.asar is built against
# this exact runtime.
#
# The bundled chrome-sandbox can't be setuid in the read-only Nix store, so the sandbox
# is wired up by the consuming module (common/claude-desktop.nix) via security.wrappers +
# CHROME_DEVEL_SANDBOX. This package intentionally does NOT pass --no-sandbox.
#
# To bump the version + hash, run scripts/update-claude-desktop.sh.
let
  inherit (pkgs) lib;

  version = "1.40609.1";
  hash = "sha256-gBguhRHGu+5t4mx+4iX70qmroidO8UBaHYnNj+ejgNw=";
in
pkgs.stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
    inherit hash;
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  # Runtime libraries for the vendored Electron/Chromium. autoPatchelfHook resolves the
  # ELF dependencies against these; wrapGAppsHook3 supplies the GTK/GIO/pixbuf env.
  buildInputs = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng # bundled virtiofsd (Cowork VM helper)
    libdrm
    libgbm
    libnotify
    libseccomp # bundled virtiofsd (Cowork VM helper)
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    libayatana-appindicator
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxtst
    libxshmfence
  ];

  # dlopen()'d at runtime, not linked. autoPatchelfHook only adds a RUNPATH entry for a
  # library that satisfies some DT_NEEDED, so listing these in buildInputs isn't enough —
  # they have to be named here or the dlopen fails at runtime.
  #
  # libsecret is what Chromium's gnome-libsecret os_crypt backend loads (see
  # --password-store in common/claude-desktop.nix). Without it KeyStorageLibsecret::Init()
  # fails, OSCrypt never derives a v11 key, safeStorage.isEncryptionAvailable() returns
  # false, and the app logs "tokens will not persist" — so the auth token is dropped on
  # exit and every launch lands on the login page.
  runtimeDependencies = with pkgs; [
    (lib.getLib systemd)
    (lib.getLib libsecret)
  ];

  # dpkg-deb -x tries to restore chrome-sandbox's setuid bit, which fails in the build
  # sandbox. Stream the payload through tar without preserving perms; the sandbox helper
  # gets its setuid bit from the module's security.wrapper at runtime instead.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/share
    cp -r usr/lib/claude-desktop $out/lib/claude-desktop
    cp -r usr/share/applications $out/share/applications
    cp -r usr/share/icons $out/share/icons

    runHook postInstall
  '';

  # wrapGAppsHook3 computes gappsWrapperArgs in preFixup; build our launcher after so the
  # GTK env is applied. xdg-utils provides xdg-open for external links.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]}
  '';

  meta = {
    description = "Desktop application for Claude.ai (official Linux build, repackaged for Nix)";
    homepage = "https://claude.ai";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
}
