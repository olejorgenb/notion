{
  enableXft ? true, libXft ? null,
  patches ? [],
  stdenv, fetchurl,
  lua, gettext, groff,
  pkgconfig, which,
  xlibsWrapper, libXinerama, libXrandr, libX11,
  cairo
}:

assert enableXft -> libXft != null;

stdenv.mkDerivation {
  name     = "notion";
  version  = "3-2015061300";
  meta = with stdenv.lib; {
    description = "Tiling tabbed window manager, follow-on to the ion window manager";
    homepage = http://notion.sourceforge.net;
    platforms = platforms.linux;
    license   = licenses.notion_lgpl;
    maintainers = [maintainers.jfb];
  };

  src = ./.;

  preConfigure="make clean";


  # patches = patches ++ stdenv.lib.optional enableXft ./notion-xft_nixos.diff;
  # postPatch = "substituteInPlace system-autodetect.mk --replace '#PRELOAD_MODULES=1' 'PRELOAD_MODULES=1'";
  buildInputs = [xlibsWrapper lua gettext groff
  which pkgconfig libXinerama libXrandr libX11 cairo] ++ stdenv.lib.optional enableXft libXft;

  buildFlags = "LUA_DIR=${lua} X11_PREFIX=/no-such-path PREFIX=\${out}";
  installFlags = "PREFIX=\${out}";

  postInstall = ''
    ln $out/lib/notion/bin/notionflux $out/bin
  '';

}
