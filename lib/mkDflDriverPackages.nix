# OFS DFL drivers for each host kernel the site provides, for example
# doctor-cluster-xilinx's driverKernels. Returns ofs-dfl-drivers-<host>.
{
  pkgs,
  driverKernels,
  src,
  version,
}:
pkgs.lib.mapAttrs' (
  host: kernel:
  pkgs.lib.nameValuePair "ofs-dfl-drivers-${host}" (
    pkgs.callPackage ../pkgs/dfl-drivers.nix { inherit kernel src version; }
  )
) driverKernels
