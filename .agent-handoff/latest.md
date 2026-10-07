# Handoff Packet (updated 2026-10-07, after JPEG 2000 Part 2)

Repo: /Users/nark/Development/Opale/Swift/DcmSwift, branch `codex/dcmswift-2.0`.
JPEG XL is committed as `5371911`; structured Person Name and multi-valued text
as `16fb028`; JPEG 2000 Part 2 `.92/.93` decode (Claude) in the commit that
updated this file. The previous Codex → Claude handoff is archived in
`2026-10-07-codex-to-claude.md`.

## Latest observations and tests
- JPEG XL `.110/.111/.112` decode is implemented with vendored libjxl 0.12.0;
  raw/container, lossless 8/12-bit, RGB, lossy, JPEG recompression, malformed
  input, and DICOM Fragment padding fixtures pass.
- macOS: `swift build -c debug`, `swift build -c release`, and
  `swift test --parallel` passed (201 tests before the PN tranche).
- iOS Simulator 26.2, iPhone 17 Pro: 198 tests, 4 skipped, 0 failures.
- Xcode emits many non-fatal `-Wshorten-64-to-32` warnings from upstream
  libjxl. They are not hidden with unsafe flags.
- Linux Swift 6.1 was not runnable locally because the Docker daemon was not
  available, but GitLab pipeline 3559 passed its `swift-package` gate at
  `a68c8f8`. The same pipeline passed `macos-package` and `ios-package`.
- Part 2 `.92/.93` is now decoded (see "Done: JPEG 2000 Part 2" below);
  OpenJPEG's own Part 2 path is still unusable and is bypassed.
- Person Name qualification after `16fb028`: `swift build -c release` passed;
  `swift test --parallel` passed 207 tests; iOS Simulator passed 204 tests with
  4 expected skips and no failures. The focused PN/charset/core group passed 73
  tests, and the final post-sort PN rerun passed all 6 PN tests.

## Project goals (from the user)
- Implement DICOM 2026d in Swift, as completely and as well as possible. Normative source: the local DocBook at `/Users/nark/Downloads/DocBookDICOM2026d_release_docbook_20260921134221/source/docbook/partNN/partNN.xml`.
- Platforms: macOS, iOS and Linux. CI runs on GitLab.
- Unit tests are required. Binary DICOM is the priority. Beat ThalesMMS/DICOM-Swift, which is Apple-only.
- **Read retired features too** (retired transfer syntaxes, JPEG processes). Old files must stay readable.
- Codecs, "option 2": pure Swift for RLE, Deflate, JPEG and JPEG-LS. JPEG 2000, HTJ2K and JPEG XL go through vendored C references (OpenJPEG, OpenJPH, libjxl), with real fast Swift versions as a later goal.
- The user writes in French; reply in French.

## Done (green on CI through d6b8cda, pipeline 3552: 530 tests)
- iOS + Apple CI.
- Corpus in CI.
- Every Specific Character Set.
- Portable pixel pipeline.
- Encapsulated frame assembly.
- RLE and Deflated Image Frame.
- JPEG Lossless decode and encode.
- JPEG Baseline/Extended decode (bit-exact with libjpeg-turbo) and encode (Codex `be320f6`).
- Arithmetic decoding `.52`/`.54`/`.56`/`.58` (Codex `d6b8cda`).
- Retired `.53`/`.55`.

## Done in 67daabd: hierarchical JPEG `.59` to `.66` (T.81 Annex J)
- `DICOMJPEGHierarchicalCodec` (registered; Baseline/Lossless `decode()` delegate when `stream.hierarchy != nil`; single-frame streams under .59-.66 fall back to Baseline/Lossless).
- Expansion follows T.81 J.1.1.2 literally (horizontal then vertical, truncating each). Richter's reference uses fixed point (COLOR_BITS), so it effectively computes (a+b+c+d)/4 at odd/odd positions: ±1 there. Lossy color vs reference ≤ 5 levels, gray ≤ 2, same PSNR vs source.
- DCT base + lossless final frame (`-y 0`, `-y 1`): reference decodes losslessly, we are ±1 (encoder's own IDCT, non-normative T.81 A.3.3). Documented in DEFERRED_LIMITATIONS.
- Lossless differential: modulo 2^16 at P=16, signed + saturation below (reference's `-p -y` streams are not self-consistent and would wrap 0→255 otherwise).
- **Bug fixed:** arithmetic lossless (SOF11/15) statistics are per DC table, not per component (T.81 B.2.3; reference `aclosslessscan.cpp`). The Codex "oxideav" RGB vector was non-conformant and was replaced by `jpeg-sof11-rgb.jpg` from the reference encoder.
- Reference encoder `-p` (predictive) crashes with "DQT marker missing"; patch `codestream/tables.cpp` `Tables::QuantizationTableIndexOf` to `return 0` when `m_pQuant == NULL`, then `make clean && make`. With the patch `-p -a -c`, `-p -c -h -y 2`, `-p -a -y 2` work. `-z N` in lossless mode writes restart intervals that are not line multiples (invalid per T.81 H.1.1).
- Fixtures: `CIResources/jpeg-hier-*.jpg/.ref` + `jpeg-hierarchical-cases.json` (UID, max and mean tolerance); test file `DcmSwiftJPEGHierarchicalTests.swift`.
- Validation: release build, `swift test --parallel` (184 XCTests), local corpus, and iOS simulator (181 tests, 3 skipped) all green. Not yet on CI (unpushed).

## Done in 93cde66: JPEG-LS `.80`/`.81` (T.87), decode and encode
- Files: `Codecs/JPEGLS/JPEGLSStream.swift` (markers, LSE type 1, APP8 mrfx, DRI), `JPEGLSScanDecoder.swift` (bit reader, `JPEGLSContextModel`, `JPEGLSLineBuffer`, decoder), `JPEGLSScanEncoder.swift` (bit writer, encoder), `DICOMJPEGLSCodec.swift`.
- Oracles: CharLS clone (`git clone https://github.com/team-charls/charls`) has the T.87 conformance suite in `test/data/conformance`; build a driver with `c++ -std=c++20 -O2 -DCHARLS_STATIC -Icharls/include -Icharls/src charls/src/*.cpp lsenc.cpp` (no cmake on this Mac). imagecodecs 2026.8.16 (CharLS 2.4.4) decodes. The pydicom test files include 8 JPEG-LS DICOM files (`pydicom.data.get_testdata_files`).
- Results: full conformance suite exact or within NEAR (identical to CharLS); encoder byte-identical to CharLS on 46 cases; pydicom files identical. Release decode is ~1.7x CharLS time.
- Full suite test: `DCMSWIFT_JPEGLS_CONFORMANCE=<charls>/test/data/conformance swift test --filter JPEGLSTests`.
- Docs layout: several short themed tables with fitting columns and HTML lists inside cells (see memory feedback-docs-lists).

## Done in 985ffb5: JPEG 2000 / HTJ2K via vendored OpenJPEG 2.5.4 (5e, part 1)
- `Sources/COpenJPEG` (upstream files unchanged, hand-written `include/opj_config.h` and `opj_config_private.h`, `README.DcmSwift.md`), target in `Package.swift` with `MUTEX_pthread`; do NOT define `OPJ_STATIC` (hidden visibility breaks Xcode/iOS linking).
- `DICOMJPEG2000Codec`: decode .90/.91/.201/.202/.203 (J2K or JP2), encode Part 1 (`Quality`: lossless, compressionRatio, peakSignalToNoiseRatio). Output photometric RGB when the COD MCT byte (marker + 8) is set.
- Pitfalls found: `size_t` imports as Int, so stream callbacks must return -1 (not `OPJ_SIZE_T.max`); objects passed as unretained context need `withExtendedLifetime`.
- Oracles: pydicom test files (`get_testdata_files`, 22 J2K/HTJ2K files; *_J2KR vs *_UNCR pairs), `pylibjpeg-openjpeg` 2.6.0 in the venv, imagecodecs 2026.8.16 bundles OpenJPH 0.31 (`htj2k_encode`) and libjxl 0.12.
- Not done: Part 2 (.92/.93), JPIP, HTJ2K encoding (OpenJPH next), JPEG XL (libjxl).

## Done in 9a44772: HTJ2K encoding via vendored OpenJPH 0.32.0 (5e, part 2)
- `Sources/COpenJPH`: upstream `src/core` unchanged minus SIMD files, `OJPH_DISABLE_SIMD`, C interface `include/copenjph.h` + `copenjph.cpp` (process-wide error handler that throws with the message; info/warning streams silenced). Package uses `cxxLanguageStandard: .cxx14`.
- `DICOMJPEG2000Codec.encodeHTJ2K(_:description:mode:)` with `HTJ2KMode` .lossless/.losslessRPCL (TLM, base resolution <= 64)/.irreversible(quantizationStep:).
- Validation: OpenJPH decoder (imagecodecs), pylibjpeg-openjpeg, and our OpenJPEG decode agree exactly on lossless output. imagecodecs' `htj2k_decode` wraps lossy uint8 output at 0/255 (no clamp): not our bug.
- Plan: new Phase 3 "Image rendering and presentation" (after network) in DICOM_2_0_IMPLEMENTATION_PLAN.md; Web/security became Phase 4. Oracle idea: DCMTK `dcmp2pgm`, IHE CPI test images.

## Done: JPEG 2000 Part 2 `.92/.93` decode (Claude)
- Normative text: ITU-T T.801 (06/2021) = ISO/IEC 15444-2, free PDF from
  `https://www.itu.int/rec/dologin_pub.asp?lang=e&id=T-REC-T.801-202106-S!!PDF-E&type=items`
  (Annex A.3.6-A.3.9 markers, Annex J); T.800 (06/2019) the same way
  (`T-REC-T.800-201906-S`) for the Annex F 1-D wavelet. `pdftotext -layout`.
- Design: OpenJPEG stays unchanged. `JPEG2000Codestream` parses main and
  tile-part headers and rewrites the codestream in place (same lengths): Rsiz
  0, COD MCT byte 0 when 2/4/6, CBD/MCT/MCC/MCO marker codes -> COM, and SIZ
  components declared signed and wider (30 bits if 5-3 everywhere, else +8
  bits: the 9-7 step sizes scale with Rb, so samples come out x256 = 8
  fractional bits). `JPEG2000ComponentTransform` then inverts Annex J in
  Double (exact for reversible). Without the widening OpenJPEG clamps the
  LL band and lossless output was off by up to 7.
- DICOM layout (PS3.5 A.4.4): `DICOMEncapsulatedPixelData` groups the
  Fragments of a multi-frame .92/.93 image by codestream start (offset tables
  ignored), decodes a collection with
  `DICOMPixelDataCollectionDecoder.decodeCollection`, caches the last one;
  frame f = components f*spp ..< (f+1)*spp. `encodedFrame` throws there.
- Oracle: Kakadu 8.4.1 demo apps for macOS (non-commercial, never in the
  repo/CI): `http://kakadusoftware.com/wp-content/uploads/KDU841_Demo_Apps_for_MacOS_231117.dmg_.zip`,
  `pkgutil --expand-full` the pkg, copy `libkdu_v84R.dylib` beside the
  binaries, `install_name_tool -change /usr/local/lib/libkdu_v84R.dylib
  @executable_path/libkdu_v84R.dylib`, `codesign -s - -f`. `kdu_compress`
  segfaults on DEP transforms and refuses differing Sprecision/Mprecision on
  directly associated irreversible components; `kdu_expand` reads neither
  split MCC series nor 16-bit indices. Dependency/multi-stage/tile-override
  fixtures were built by injecting segments into Kakadu Part 1 codestreams
  (generator scripts were scratch only; the approach is described in the
  test file header).
- Results: 14 fixtures, all reversible ones bit-exact with Kakadu, 9-7 DWT
  exact, irreversible matrix/dependency within 1. 64x512x512 12-bit 5-3
  volume: identical to Kakadu, 0.57 s release (Kakadu 0.35 s). OpenJPEG
  decoding now uses `opj_codec_set_threads` (2.6 s -> 0.3 s on that volume).
- Qualification: `swift build -c release`, `swift test --parallel` (213
  tests), iOS Simulator 26.2 iPhone 17 Pro (210 tests, 4 expected skips, 0
  failures), plus a scratch header fuzz (~6000 corrupted main headers, no
  crash). Not yet run on GitLab CI.
- Not done: Part 2 encode; no external DICOM .92/.93 corpus known.

### B. JPEG XL (.110 lossless, .111 JPEG recompression, .112 lossy) — done
- `Sources/CJPEGXL` vendors the decoder sources from libjxl 0.12.0 commit
  `a7a9c787341cf703dede03c2009fa460cae5e5df` and its pinned Highway runtime.
- `DICOMJPEGXLCodec` decodes unsigned integer mono/RGB streams to native
  interleaved pixels and rejects unsupported signed/float, extra-channel,
  animation, and non-identity-orientation inputs explicitly.
- `.111` is decoded to pixels; original-JPEG reconstruction is not exposed.
- The package C++ language level is now C++17. OpenJPEG and OpenJPH build and
  test successfully at that level.

### Conventions reminder
Docs as several short tables with HTML lists in cells (memory: feedback-docs-lists); never `rm` with wildcards; commit message style with trailer; before each commit run release build, `swift test --parallel`, iOS xcodebuild with a fresh derivedDataPath.

## Next
- JPEG 2000 Part 2 encode (optional: e.g. reversible 5-3 across frames via
  OpenJPEG components + our forward transform, Kakadu as oracle);
- then 6: fuzzing, DCMTK/pydicom cross-checks, PS3.18 JSON / PS3.19 XML, network rewrite (NIOAsyncChannel, swift-nio-ssl, transport-services);
- then 7: rendering and presentation (plan Phase 3: PS3.4 Annex N, GSPS/CSPS, overlays, shutters, padding, Presentation LUT + GSDF, ICC, high bit depth, RWVM).

## Conventions and methods that work
- Every codec is checked against an independent reference **before** committing:
  - the PS3.5 annexes, as normative vectors;
  - libjpeg-turbo, through Python `imagecodecs` and `Pillow`;
  - pydicom 3, pylibjpeg and numpy, installed in a disposable venv (`python3 -m venv /tmp/x && pip install pydicom numpy imagecodecs pylibjpeg pylibjpeg-libjpeg pillow`).
  - Temporary `Tests/DcmSwiftTests/ZZ*.swift` tests dump values, Python compares them, then the ZZ tests are deleted.
- **Known divergence:** pylibjpeg gets the point transform wrong for JPEG Lossless (2^(P−1) instead of 2^(P−Pt−1)). libjpeg-turbo is the reference there.
- The corpus is local only (`Tests/DcmSwiftTests/Resources`, confidential, git-ignored). Run: `DCMSWIFT_REQUIRE_INTEROP_CORPUS=1 DCMSWIFT_INTEROP_CORPUS=$PWD/Tests/DcmSwiftTests/Resources swift test --filter 'DcmSwiftTests.DcmSwiftTests/testExternalDICOMCorpus'`.
- Small synthetic fixtures go in `Tests/DcmSwiftTests/CIResources` (`.process`, flat names like `jpeg-*.jpg/.ref`).
- For every change, update together: `README.md` and `Documentation/DICOM_CONFORMANCE.md`, `DICOM_DEFERRED_LIMITATIONS.md`, `DICOM_TRACEABILITY.md` (test names), `DICOM_2_0_IMPLEMENTATION_PLAN.md`.
- **Before each commit:**
  - `swift build -c release`;
  - `swift test --parallel` (that's how CI runs it);
  - for anything touching resources, iOS: `xcodebuild test -scheme DcmSwift-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -derivedDataPath <fresh dir>`.
- **Commits:** imperative English, explanatory paragraphs, ending with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (adapt for Codex).
- Current state: 213 XCTests green locally on macOS after JPEG 2000 Part 2.

## CI / GitLab
- `http://gitlab.dev.opale.pro` (HTTP only), project `rw/dcmswift`. The API token is in `.env` (git-ignored); never print it or commit it.
- Runners:
  - `deploy`: Linux, `swift:6.1`;
  - `swift`: Mac mini with Xcode 26.3. The iOS job uses its own `-derivedDataPath .derived-data`, because the shared DerivedData left a stale resource bundle in place.
- Useful endpoints:
  - `/api/v4/projects/rw%2Fdcmswift/pipelines?sha=`
  - `/pipelines/<id>/jobs`
  - `/jobs/<id>/trace`
  - `/pipelines/<id>/test_report_summary`

## Useful files
- `Sources/DcmSwift/Imaging/`: `DICOMPixelDescription`, `DICOMNativePixelData`, `DICOMEncapsulatedPixelData`, `DICOMImageRenderer`, `DICOMPixelDataCodec` (registry), `DICOMLookupTable`, `DICOMPNGEncoder`.
- `Codecs/`: `DICOMRLECodec`, `DICOMDeflatedFrameCodec`, `DICOMJPEGLosslessCodec` (decode and encode), `DICOMJPEGBaselineCodec` (decoder plus `JPEGDCTDecoder`).
- `Codecs/JPEG/`: `JPEGStream`, `JPEGHuffman` (table, bit reader, K.2 encoder, writer), `JPEGIDCT`, `JPEGFDCT` (WIP).
