{ pkgs, ... }:
# ChatGPT Desktop, repackaged from OpenAI's official Linux .deb (preview, launched
# 2026-08-11). The app is the Codex Electron shell under a "chatgpt" brand — its
# package.json is productName "Codex", and it reads CODEX_HOME (default ~/.codex),
# so it shares config with the standalone codex CLI managed in common/codex.nix.
#
# usr/lib/chatgpt/ChatGPT is the vendored Electron ELF (v42.3.0 / Chrome 151) and
# usr/bin/chatgpt is a symlink to codex-launcher, a two-line sh shim that just execs
# ChatGPT. We patchelf the vendored Electron against nixpkgs libs rather than swapping
# in nixpkgs' electron, because nixpkgs has no electron_42 and the app.asar is built
# against this exact runtime.
#
# Unlike claude-desktop, this .deb ships NO chrome-sandbox helper: its AppArmor profile
# only requests `userns`, i.e. it relies on unprivileged user namespaces for the
# Chromium sandbox. NixOS enables those by default, so no setuid wrapper is needed and
# we do NOT pass --no-sandbox.
#
# To bump the version + hash, run scripts/update-chatgpt-desktop.sh.
let
  inherit (pkgs) lib;

  version = "26.825.51511";
  hash = "sha256-NVSwAixs+1EzJvQ/0R9xiDWncIasTXyi/z67ui1Mf0U=";
in
pkgs.stdenv.mkDerivation {
  pname = "chatgpt-desktop";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    inherit hash;
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  # Runtime libraries for the vendored Electron/Chromium, derived from the ELF's
  # DT_NEEDED plus the .deb's Depends. autoPatchelfHook resolves against these;
  # wrapGAppsHook3 supplies the GTK/GIO/pixbuf env.
  buildInputs = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    graphite2
    gtk3
    libdrm
    libgbm
    libglvnd # libGL, from the deb's libgl1 dependency
    libnotify
    libsecret # dlopen'd by Electron safeStorage (see --password-store in the module)
    libusb1
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxshmfence
    libxtst
  ];

  # dlopen()'d at runtime rather than linked, so they never appear in DT_NEEDED and
  # autoPatchelf won't add them to RPATH from buildInputs alone. libGL in particular is
  # loaded by ANGLE during GPU init; without it the app logs a flood of
  # "Could not dlopen libGL.so.1" and falls back off hardware acceleration. libsecret is
  # loaded by Chromium's gnome-libsecret os_crypt backend; without it safeStorage reports
  # isEncryptionAvailable=false and the session token is never persisted, so every launch
  # asks for a fresh login.
  runtimeDependencies = [
    (lib.getLib pkgs.systemd)
    pkgs.libglvnd
    (lib.getLib pkgs.libsecret)
  ];

  # The app bundles a large pile of third-party native helpers under resources/ —
  # node, ripgrep, tectonic, sharp/libvips, better-sqlite3, node-pty, skia — including
  # prebuilds for other architectures (android-arm, arm64) and musl variants. Those
  # aren't loadable here and would abort the build on unresolved deps, so don't treat
  # missing dependencies as fatal. The main Electron binary's deps are all satisfied
  # above; this only relaxes the long tail.
  autoPatchelfIgnoreMissingDeps = true;

  # Keep dpkg-deb from restoring ownership/permissions it can't set in the build sandbox.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/share
    cp -r usr/lib/chatgpt $out/lib/chatgpt
    cp -r usr/share/applications $out/share/applications
    cp -r usr/share/pixmaps $out/share/pixmaps

    runHook postInstall
  '';

  # wrapGAppsHook3 computes gappsWrapperArgs in preFixup; build our launcher after so the
  # GTK env is applied. xdg-utils provides xdg-open for external links; git is a Recommends
  # and is used by the bundled Codex for repo operations.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapper $out/lib/chatgpt/ChatGPT $out/bin/chatgpt \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.git
          pkgs.xdg-utils
        ]
      }
  '';

  meta = {
    description = "Desktop application for ChatGPT (official Linux build, repackaged for Nix)";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
}
