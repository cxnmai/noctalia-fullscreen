{ lib, stdenv, zig_0_15 }:
stdenv.mkDerivation {
  pname = "noctalia-fullscreen";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ zig_0_15 ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
    zig build -Doptimize=ReleaseSmall --prefix "$out"
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = "zig build test";
  installPhase = "true";
  meta = {
    description = "Tiny event-driven Noctalia fullscreen auto-hide helper for Niri";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "noctalia-fullscreen";
  };
}
