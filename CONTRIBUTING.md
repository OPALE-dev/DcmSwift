# Contributing to DcmSwift

Thank you for your interest in DcmSwift. This guide explains how to propose a
change and what a change needs before it is merged. By participating, you
agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Search the existing issues, and open one before a large change so its scope
  can be agreed first.
- Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).
- Never attach or commit files that contain patient data. Test fixtures must be
  synthetic or come from a public, redistributable source.

## Build and test

```sh
swift build -c release
swift test --parallel
```

Changes that touch resources, codecs, or platform code must also pass on iOS
and Linux. The commands, the optional interoperability corpus, and the
cross-checks with pydicom, pynetdicom, and DCMTK are described in
[Testing and Qualification](Sources/DcmSwift/DcmSwift.docc/Guides/TestingAndQualification.md).
CI runs the same jobs on GitHub Actions and GitLab CI.

## What a change needs

DcmSwift follows the release gates of its
[implementation plan](Sources/DcmSwift/DcmSwift.docc/Qualification/ImplementationPlan.md):

| Requirement | Details |
| --- | --- |
| Normative reference | Cite the DICOM 2026d part and section that the change implements |
| Tests | Automated tests for every new claim; small synthetic fixtures go in `Tests/DcmSwiftTests/CIResources` |
| Independent check | Codecs, encodings, and network behavior are compared with an independent implementation (libjpeg-turbo, OpenJPEG, CharLS, pydicom, pynetdicom, DCMTK, …) before they are merged |
| Platforms | The package builds and the tests pass on macOS, iOS, and Linux |
| Documentation | Update the README coverage tables and, in `Sources/DcmSwift/DcmSwift.docc/Qualification`, the Conformance Statement, the traceability matrix, and the limitations register in the same change; the DocC site must build without warnings |
| Compatibility | Source or behavior changes come with a migration note in the pull request |

Build the documentation with:

```sh
Scripts/documentation/build.sh .build/documentation
```

## Style

- Follow the style of the surrounding code: naming, comment density, and
  idioms.
- Public API is documented with `///` comments that name every parameter.
- Keep commits focused. Write commit messages in English, in the imperative
  mood (`Add …`, `Fix …`, `Remove …`), with a short summary line and an
  explanatory paragraph when the reason is not obvious. The changelog is
  generated from these summaries with [git-cliff](https://git-cliff.org).

## Pull requests

Open pull requests against `master`. Describe what changes, why, the normative
reference, and how it was verified. CI must pass before review.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
