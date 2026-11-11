# Build an OFS FIM (the FPGA shell) with OFS's own build_top.sh, run inside
# fpga-nix's Quartus environment on fpga-nix's stage builder.
#
# Installs the FIM's output_files (.sof, flash images and reports) and, with
# prTemplate, the relocatable PR build template that AFUs are built against.
{
  pkgs,
  fpgaNixLib,
  # The result of fpga-nix's mkIntelTools for the site's installation.
  intelTools,
  quartusShareRoot,
  # Must be the version the OFS release was made for.
  quartusVersion,
  # The OFS FIM source with its ofs-common submodule.
  src,
  # ofs-platform-afu-bbb from the same OFS release, used for the PR template.
  platformAfuBbb,
  # OPAE's PACSign, packager and afu_json_mgr. Without them on PATH, the build
  # clones OPAE's master branch from GitHub.
  opae,
  # A board under syn/board, for example "iseries-dk".
  target,
  # Extra .ofss files on top of the board's default IP configuration.
  ofss ? [ ],
  prTemplate ? true,
  licenseFile ? null,
  pname ? "ofs-fim-${target}",
  version ? "0.1.0",
  cores ? 16,
  extraAttrs ? { },
}:
let
  inherit (pkgs) lib;

  synTop = "work/syn/board/${target}/syn_top";

  buildFlags =
    lib.optional prTemplate "-p"
    ++ lib.optionals (ofss != [ ]) [
      "--ofss"
      (lib.concatMapStringsSep "," toString ofss)
    ];
in
fpgaNixLib.mkStagePackage {
  inherit
    pkgs
    pname
    version
    src
    cores
    extraAttrs
    ;
  tools = intelTools.all ++ [ opae ];
  # Tools OFS's scripts call directly.
  nativeBuildInputs = [
    pkgs.git
    pkgs.perl
    pkgs.python3
    pkgs.rsync
    pkgs.which
  ];
  toolRoots = [ quartusShareRoot ];
  env = {
    FPGA_NIX_QUARTUS_VERSION = quartusVersion;
    OFS_PLATFORM_AFU_BBB = toString platformAfuBbb;
  }
  // lib.optionalAttrs (licenseFile != null) {
    FPGA_NIX_QUARTUS_LICENSE_FILE = toString licenseFile;
  };
  executionKind = "ofs-fim-stage-execution";
  buildCommands = [
    ''export OFS_ROOTDIR="$PWD"''
    (lib.escapeShellArgs (
      [
        "quartus-env"
        "bash"
        "ofs-common/scripts/common/syn/build_top.sh"
      ]
      ++ buildFlags
      ++ [
        target
        "work"
      ]
    ))
  ];
  expectedPaths = [
    "${synTop}/output_files/ofs_top.sof"
  ]
  ++ lib.optional prTemplate "work/pr_build_template";
  installPaths = [
    "${synTop}/output_files"
  ]
  ++ lib.optional prTemplate "work/pr_build_template";
  description = "OFS FIM for ${target}";
  platforms = [ "x86_64-linux" ];
}
