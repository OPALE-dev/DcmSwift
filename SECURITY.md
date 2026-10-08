# Security Policy

DcmSwift parses untrusted files and network input (DICOM Part 10 files, DICOM
JSON and XML, DIMSE associations, TLS). Security reports are welcome and are
handled privately until a fix is available.

## Supported versions

| Version | Supported |
| --- | --- |
| `master` (DcmSwift 2.0 development) | ✓ |
| 0.x releases | ✗ |

## Reporting a vulnerability

Do not open a public issue. Use one of these private channels:

- GitHub: **Security → Report a vulnerability** on
  [OPALE-dev/DcmSwift](https://github.com/OPALE-dev/DcmSwift/security/advisories/new);
- email: rw@opale.pro.

Please include the affected revision, the platform, and a minimal reproducer.
Do not attach files that contain patient data: reduce the input to a synthetic
case, or describe how to build one.

You can expect an acknowledgement within five working days. Once a fix is
available, it is released with a GitHub Security Advisory that credits the
reporter, unless you prefer to stay anonymous.

## Scope

In scope:

- memory safety, crashes, hangs, or unbounded resource use when reading
  malformed files, data sets, codestreams, or network PDUs;
- TLS configuration or certificate validation defects;
- path traversal or file overwrite in the command-line tools and `DcmServer`.

Out of scope: `DcmServer` deployments without access control, audit logging,
or network isolation. It is a demonstrator and interoperability tool, not a
hardened PACS; see its documentation.

DcmSwift is not a medical device and must not be used for diagnosis.
