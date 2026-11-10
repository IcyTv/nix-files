{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  libusb1,
  openssl,
  libfprint-tod,
  gusb,
  glib,
}:
stdenv.mkDerivation {
  pname = "synaptics-00e7-fpdrv";
  version = "0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "HansHoogerwerf";
    repo = "synaptics-00e7-fpdrv";
    rev = "53ec1fca4b73608f7f62cbd64dd9eb643041228f";
    hash = "sha256-WYLsoTDH0sK3GoySbbzvdl0YbPsMs5hdI4ImqW++8XY=";
  };

  patches = [./selftest.patch];
  nativeBuildInputs = [pkg-config];
  buildInputs = [libusb1 openssl libfprint-tod gusb glib];

  buildPhase = ''
    runHook preBuild
    make -j "$NIX_BUILD_CORES"
    # The private TOD pkg-config entry omits the public fprint.h path.
    make -C tod -j "$NIX_BUILD_CORES" \
      PKGS='libfprint-2-tod-1 libfprint-2 gusb glib-2.0 gobject-2.0 gio-2.0 libcrypto libusb-1.0'
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    # This command exits before USB access; no real pairing data is used.
    test ! -e /dev/bus/usb
    timeout 30 ./fpdrv selftest
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    # Never invoke upstream's install target: it installs/reloads udev rules.
    install -Dm755 fpdrv "$out/bin/fpdrv"
    install -Dm755 tod/libfpdrv_00e7_tod.so "$out/lib/libfprint-2/tod-1/libfpdrv_00e7_tod.so"
    runHook postInstall
  '';

  passthru.driverPath = "/lib/libfprint-2/tod-1";

  meta = {
    description = "Experimental native driver for the Synaptics 06cb:00e7 fingerprint sensor";
    homepage = "https://github.com/HansHoogerwerf/synaptics-00e7-fpdrv";
    license = lib.licenses.gpl3Only;
    platforms = ["x86_64-linux"];
    mainProgram = "fpdrv";
  };
}
