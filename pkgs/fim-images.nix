# Intel's prebuilt FIM release images for one board: the FIM (.sof), the
# default AFU (.gbs), the FME interface ID and the PR build template. Loading
# them needs no Quartus license, unlike building the FIM.
{
  lib,
  stdenvNoCC,
  fetchurl,
  release,
  board,
  hash,
}:
stdenvNoCC.mkDerivation {
  pname = "ofs-fim-images-${board}";
  version = release;

  src = fetchurl {
    url = "https://github.com/OFS/ofs-agx7-pcie-attach/releases/download/ofs-${release}/${board}-images_ofs-${
      lib.replaceStrings [ "." ] [ "-" ] release
    }.tar.gz";
    inherit hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    test -f "$out/ofs_top.sof"
    runHook postInstall
  '';

  meta = {
    description = "Prebuilt OFS ${release} FIM images for ${board}";
    homepage = "https://github.com/OFS/ofs-agx7-pcie-attach/releases/tag/ofs-${release}";
    # Built with Intel IP; redistributed by Intel on GitHub.
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.all;
  };
}
