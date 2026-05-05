{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "roost";
  version = "1.2.1";

  src = fetchurl {
    url = "https://github.com/NextAlone/Roost/releases/download/v${version}/Roost-${version}-arm64.zip";
    hash = "sha256-4aR0ahmeHAXedhIy5cPuw4e0iCdE7T8Bzpk+UlOSeOw=";
  };

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    /usr/bin/ditto -x -k "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R Roost.app "$out/Applications/Roost.app"
    ln -s "$out/Applications/Roost.app/Contents/MacOS/Roost" "$out/bin/roost"

    runHook postInstall
  '';

  meta = {
    description = "macOS native, jj-first terminal orchestration for multiple coding agents";
    homepage = "https://github.com/NextAlone/Roost";
    license = lib.licenses.mit;
    mainProgram = "roost";
    platforms = [ "aarch64-darwin" ];
  };
}
