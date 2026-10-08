# DcmSign

Verify the Digital Signatures of DICOM files, or sign them with the Base RSA
Digital Signature Profile (PS3.15 C.1).

```sh
DcmSign signed.dcm
DcmSign image.dcm --key key.pem --certificate certificate.pem --output signed.dcm
DcmSign image.dcm --key key.pem --certificate certificate.pem --tag 0008,0018 --tag 7FE0,0010 --output signed.dcm
```

| Option | Effect |
| --- | --- |
| `--key`, `--certificate` | PEM files of the RSA private key and of the signer's X.509 certificate: the file is signed |
| `--algorithm` | MAC algorithm: SHA1, SHA256 (default), SHA384, or SHA512 |
| `--tag` | A Data Element to sign; all that may be signed by default |
| `--output` | The signed file |

Without `--key`, every signature, in Sequence Items too, is verified, whatever
its MAC algorithm, RIPEMD-160 and MD5 included. The exit status is 1 when one
is not valid. The certificates are not checked against trusted authorities.
