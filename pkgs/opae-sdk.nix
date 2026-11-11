# The OPAE SDK: the user-space library and tools for OFS FPGA cards, such as
# fpgainfo and fpgaconf. nixpkgs dropped its opae package in 2025.
{
  lib,
  stdenv,
  src,
  version,
  cmake,
  pkg-config,
  python3,
  makeWrapper,
  doxygen ? null,
  cli11,
  fmt,
  hwloc,
  json_c,
  libedit,
  libuuid,
  numactl,
  spdlog,
  tbb,
}:
let
  # Modules the installed Python tools import at run time.
  pythonRuntime = ps: [
    ps.jsonschema
    ps.pyyaml
  ];

  python = python3.withPackages (
    ps:
    pythonRuntime ps
    ++ [
      ps.pip
      ps.pybind11
      ps.setuptools
      ps.setuptools-scm
      ps.wheel
    ]
  );
in
stdenv.mkDerivation {
  pname = "opae-sdk";
  inherit version src;

  nativeBuildInputs = [
    cmake
    pkg-config
    python
    python3.pkgs.wrapPython
    makeWrapper
  ];

  pythonPath = pythonRuntime python3.pkgs;

  buildInputs = [
    cli11
    fmt
    hwloc
    json_c
    libedit
    libuuid
    numactl
    python
    spdlog
    tbb
  ];

  postPatch = ''
    # OPAE adds -pie to the shared library link flags, which makes the linker
    # treat libraries as executables and look for main().
    substituteInPlace cmake/modules/OPAECompiler.cmake \
      --replace-fail 'set(CMAKE_SHARED_LINKER_FLAGS "''${CMAKE_SHARED_LINKER_FLAGS} -pie")' ""

    # The Python tools are installed with pip. Use only the packages in the
    # build environment and never contact a package index.
    grep -rl --include=CMakeLists.txt -e '-m pip install' . | while read -r file; do
      substituteInPlace "$file" \
        --replace-fail "-m pip install" "-m pip install --no-build-isolation --no-index"
    done
    substituteInPlace cmake/modules/OPAEPackaging.cmake \
      --replace-fail "-m pip install \\" "-m pip install --no-build-isolation --no-index \\"

    # Install every library into lib, not some into lib64.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'set(OPAE_LIB_INSTALL_DIR "lib64"' 'set(OPAE_LIB_INSTALL_DIR "lib"'

    # The install step ignores pip failures. Make them fatal.
    workdir='^ *WORKING_DIRECTORY ''${OPAE_PYTHON_INSTALL_SOURCE_DIR}$'
    sed -i "/$workdir/a COMMAND_ERROR_IS_FATAL ANY" cmake/modules/OPAEPackaging.cmake
    test "$(grep -c '^COMMAND_ERROR_IS_FATAL ANY$' cmake/modules/OPAEPackaging.cmake)" = 1
  '';

  env = {
    PIP_DISABLE_PIP_VERSION_CHECK = "1";
    # setuptools-scm reads the version from Git, which the source lacks.
    SETUPTOOLS_SCM_PRETEND_VERSION = lib.head (lib.splitString "-" version);
  };

  # Let the Python tools find their own modules and runtime dependencies.
  # Some tools, such as opae.io, are C++ programs that embed Python.
  postFixup = ''
    wrapPythonPrograms
    for program in "$out"/bin/*; do
      if isELF "$program" && patchelf --print-needed "$program" | grep -q '^libpython'; then
        wrapProgram "$program" --prefix PYTHONPATH : \
          "$out/${python3.sitePackages}:${python3.pkgs.makePythonPath (pythonRuntime python3.pkgs)}"
      fi
    done
  '';

  cmakeFlags = [
    # Every dependency comes from nixpkgs. Never download one during the build.
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
    "-DOPAE_BUILD_TESTS=OFF"
    # Record the library directory in the installed binaries.
    "-DOPAE_INSTALL_RPATH=ON"
    "-DOPAE_BUILD_SPHINX_DOC=OFF"
  ];

  meta = {
    description = "Open Programmable Acceleration Engine (OPAE) SDK";
    homepage = "https://github.com/OFS/opae-sdk";
    license = with lib.licenses; [
      bsd3
      mit
    ];
    platforms = lib.platforms.linux;
  };
}
