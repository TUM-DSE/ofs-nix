# Out-of-tree DFL (Device Feature List) drivers from OFS's linux-dfl-backport
# for one kernel. Mainline dfl-pci does not know the PCI IDs of current OFS
# shells, such as 8086:bcce on the Agilex 7 PCIe attach FIM.
{
  lib,
  stdenv,
  src,
  version,
  kernel,
}:
stdenv.mkDerivation {
  pname = "ofs-dfl-drivers";
  version = "${version}-${kernel.modDirVersion}";
  inherit src;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  enableParallelBuilding = true;

  # Only the kernel build directory: the kernel's own makeFlags are for
  # building the kernel itself and break an external module build.
  makeFlags = [
    "KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    # The Makefile derives these from Git, which the source lacks.
    "BACKPORT_VERSION=${version}"
    "BACKPORT_RELEASE=1"
  ];

  installPhase = ''
    runHook preInstall
    dir="$out/lib/modules/${kernel.modDirVersion}/extra/ofs-dfl"
    mkdir -p "$dir"
    find . -name '*.ko' -exec install -m644 -t "$dir" {} +
    test -n "$(ls "$dir")"
    runHook postInstall
  '';

  meta = {
    description = "OFS DFL kernel drivers for Linux ${kernel.modDirVersion}";
    homepage = "https://github.com/OFS/linux-dfl-backport";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
