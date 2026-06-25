{ rocm-systems }: final: prev: let
  nightlyVersion = "99.0.0";

  # Point src directly at the project subdirectory inside the rocm-systems
  # monorepo so we don't need any sourceRoot/postUnpack contortions.
  nightlySrc = project: {
    version = nightlyVersion;
    src = "${rocm-systems}/projects/${project}";
    sourceRoot = null;
  };

  esmiIbSrc = final.fetchFromGitHub {
    owner = "amd";
    repo = "esmi_ib_library";
    rev = "esmi_pkg_ver-5.1.1";
    hash = "sha256-I09JTi6I6Ny2Oso7Uitu6EgrtkTEfHmH45jYWdr1cpk=";
  };
in {
  rocmPackages = prev.rocmPackages.overrideScope (rocmFinal: rocmPrev: {
    rocm-core = rocmPrev.rocm-core.overrideAttrs (_: nightlySrc "rocm-core");

    rocm-smi = rocmPrev.rocm-smi.overrideAttrs (_: nightlySrc "rocm-smi-lib");

    rocm-runtime = rocmPrev.rocm-runtime.overrideAttrs (old:
      nightlySrc "rocr-runtime"
      // {
        patches = [ ];
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace runtime/hsa-runtime/core/runtime/trap_handler/CMakeLists.txt \
              --replace-fail '"gfx900;gfx942;gfx950;gfx1010;gfx1030;gfx1100;gfx1200;gfx1250"' \
                               '"gfx900;gfx942;gfx1010;gfx1030;gfx1100"' \
              --replace-fail '"9;942;950;1010;10;11;12;1250"' \
                               '"9;942;1010;10;11"' \
              --replace-fail '";;;;;;_gfx12;_gfx12"' '";;;;"'
            substituteInPlace runtime/hsa-runtime/core/runtime/amd_gpu_agent.cpp \
              --replace-fail 'kCodeTrapHandlerV2_1250, sizeof(kCodeTrapHandlerV2_1250), 2, 4},  // gfx1250' \
                               'kCodeTrapHandlerV2_11, sizeof(kCodeTrapHandlerV2_11), 2, 4},  // gfx1250' \
              --replace-fail 'kCodeTrapHandlerV2_12, sizeof(kCodeTrapHandlerV2_12), 2, 4},    // gfx12' \
                               'kCodeTrapHandlerV2_11, sizeof(kCodeTrapHandlerV2_11), 2, 4},    // gfx12'
          '';
      });

    rocminfo = rocmPrev.rocminfo.overrideAttrs (_: nightlySrc "rocminfo");

    amdsmi = rocmPrev.amdsmi.overrideAttrs (old:
      nightlySrc "amdsmi"
      // {
        patches = [ ];
        buildInputs = old.buildInputs ++ [ final.libnl final.libmnl ];
        postPatch =
          (old.postPatch or "")
          + ''
            rm -rf ./esmi_ib_library
            cp -rf --no-preserve=mode ${esmiIbSrc} ./esmi_ib_library
            mkdir -p ./esmi_ib_library/include/asm
            cp ./include/amd_smi/impl/amd_hsmp.h ./esmi_ib_library/include/asm/amd_hsmp.h
          '';
      });

    aqlprofile = rocmPrev.aqlprofile.overrideAttrs (_: nightlySrc "aqlprofile");

    rdc = rocmPrev.rdc.overrideAttrs (_: nightlySrc "rdc");

    hip-common = rocmPrev.hip-common.overrideAttrs (_: nightlySrc "hip");

    clr = rocmPrev.clr.overrideAttrs (_: nightlySrc "clr");

    roctracer = rocmPrev.roctracer.overrideAttrs (_: nightlySrc "roctracer");

    rocprofiler-register = rocmPrev.rocprofiler-register.overrideAttrs (_:
      nightlySrc "rocprofiler-register"
      // { patches = [ ]; });

    rocprof-trace-decoder = rocmPrev.rocprof-trace-decoder.overrideAttrs (_:
      nightlySrc "rocprof-trace-decoder"
      // {
        patches = [ ];
        doCheck = false;
        env.CXXFLAGS = "-Wno-error=narrowing";
      });
  });
}
