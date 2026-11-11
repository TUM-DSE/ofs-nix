# ofs-nix

Nix tooling for Intel's [Open FPGA Stack (OFS)](https://ofs.github.io), built
on [fpga-nix](https://github.com/TUM-DSE/fpga-nix). It plays the role for OFS
that coyote-nix plays for Coyote: it builds the FPGA shell (the FIM), the host
software (OPAE) and the kernel drivers.

The pinned release is OFS 2024.2, the newest one for Quartus Prime Pro 24.1.
It supports the Agilex 7 FPGA I-Series Development Kit (`iseries-dk`).

## Status

- OPAE SDK 2.13.0-3: builds, and every tool starts.
- DFL kernel drivers: build for nixpkgs' 6.6 kernel and for xavier's 6.0
  kernel. Not yet loaded on a host.
- FIM: the build runs OFS's own scripts through work directory setup. It stops
  at IP generation, because Quartus only offers Agilex 7 with a license.
- AFUs and deployment: not started.

## Library

### mkOfsFimPackage

```nix
ofs-nix.lib.mkOfsFimPackage {
  inherit pkgs;
  intelTools = fpga-nix.lib.mkIntelTools {
    inherit pkgs;
    quartusShareRoot = "/share/intel-fpga/tools";
  };
  quartusShareRoot = "/share/intel-fpga/tools";
  quartusVersion = ofs-nix.lib.quartusVersion; # "24.1"
  target = "iseries-dk";
  licenseFile = "/path/to/license.dat";
}
```

Runs `build_top.sh` from the FIM source inside fpga-nix's Quartus environment
and installs the board's `output_files` and, unless `prTemplate = false`, the
relocatable `pr_build_template` that AFUs are built against. Extra `.ofss`
files go in `ofss`.

OFS's scripts would clone repositories during the build. ofs-nix provides
them instead: the OPAE package supplies `PACSign`, `packager` and
`afu_json_mgr`, and `OFS_PLATFORM_AFU_BBB` points at the pinned
`ofs-platform-afu-bbb`.

Requirements outside Nix:

- a Quartus license for Agilex 7,
- Quartus 24.1 patches 0.18 and 0.26, which the OFS 2024.2 release requires,
- the OFS IP license from `license/quartus-0.0-0.02iofs-linux.run` in the FIM
  source, installed into the Quartus installation,
- the Quartus installation visible in the build sandbox (`extra-sandbox-paths`).

### mkDflDriverPackages

```nix
ofs-nix.lib.mkDflDriverPackages {
  inherit pkgs;
  driverKernels = site.driverKernels;
}
```

Builds OFS's out-of-tree DFL drivers (`linux-dfl-backport`) for each host
kernel, as `ofs-dfl-drivers-<host>`. Mainline `dfl-pci` does not know the PCI
IDs of current OFS shells, such as `8086:bcce`.

## Packages

- `opae`: the OPAE SDK. nixpkgs removed its package in 2025.
- `fim-images-iseries-dk`: Intel's prebuilt OFS 2024.2 FIM for the I-Series
  dev kit (`ofs_top.sof`, the default AFU `.gbs`, the FME interface ID and the
  PR build template). Loading it needs no Quartus license.
