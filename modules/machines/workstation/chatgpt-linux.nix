{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libusb1,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxcb,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  xdg-utils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "chatgpt";
  version = "26.825.41651";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${finalAttrs.version}_amd64.deb";
    hash = "sha256-IbIulcDEOj8RTz7TJpKr7cY49AV6CPmMmINuLT6aZx4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libusb1
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxcb
    mesa
    nspr
    nss
    pango
    systemd
  ];

  /*
    The archive carries both glibc and musl Node prebuilds; only glibc is
    selected on this host. It also carries optional Qt 5 and Qt 6 desktop-
    integration shims, neither of which Hyprland loads. Pulling both Qt stacks
    into one derivation triggers Nix's deliberate mixed-Qt-hook rejection.
  */
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r usr/* "$out/"
    rm "$out/bin/chatgpt"
    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "--ozone-platform-hint=auto"
    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT desktop application for Linux";
    homepage = "https://chatgpt.com/download/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "chatgpt";
  };
})
