{
  enableXft ? true, libXft ? null,
  patches ? [],
  stdenv, fetchurl,
  lua, gettext, groff,
  pkgconfig, which,
  xlibsWrapper, libXinerama, libXrandr, libX11, cairo,
  fetchgit,
  clutter, glib, libXrender, libXcomposite,
  gnome3, gobjectIntrospection

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

  src = fetchgit {
    url = /home/ole/src/notion/notion;
    rev = "refs/heads/develop"; # develop
    sha256 = "1d8q9954sxkm670hfy4bcwv4d0i4ax23pbig8cicc9jrw340xyh9";
  };
  # src = /home/ole/src/notion/notion/.;

  dontStrip = true;
  enableParallelBuilding = true;

  preConfigure = '' make realclean '';

  # patches = patches ++ stdenv.lib.optional enableXft ./notion-xft_nixos.diff;
  # postPatch = "substituteInPlace system-autodetect.mk --replace '#PRELOAD_MODULES=1' 'PRELOAD_MODULES=1'";
  propagatedBuildInputs = [ stdenv xlibsWrapper lua gettext groff which pkgconfig libXinerama libXrandr libX11 cairo ] ++ stdenv.lib.optional enableXft libXft
  ++ [ glib clutter ] ++ [ gnome3.gjs gobjectIntrospection ] 
    ++ [ libXrender libXcomposite ];

  buildFlags = "LUA_DIR=${lua} X11_PREFIX=/no-such-path PREFIX=\${out}";
  installFlags = "PREFIX=\${out}";

  postInstall = ''
    ln $out/lib/notion/bin/notionflux $out/bin
  '';

}
