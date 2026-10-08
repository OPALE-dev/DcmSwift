# DcmServer

Serve verification, storage, Query/Retrieve, and Storage Commitment over a
directory.

```sh
DcmServer --aet DCMSERVER --port 11112
DcmServer --aet ARCHIVE --storage-directory ./archive --port 11112
DcmServer -a DCMSERVER -p 11112 -s /data/archive --destination VIEWER=10.0.0.5:104
```

Without `--storage-directory`, only C-ECHO is served. With a storage directory,
received instances are persisted and indexed for C-FIND, C-MOVE, and C-GET.
Move destinations and Storage Commitment callback destinations use repeated
`--destination AET=host:port` options. TLS and mutual TLS are available through
the certificate, key, and client-CA options.

This is a demonstrator and interoperability tool. Production deployment still
requires access control, durable indexing, audit logging, monitoring, backup,
and an operational security review.
