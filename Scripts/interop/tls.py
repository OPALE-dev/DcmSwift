"""DICOM over TLS between pynetdicom (Python ssl, OpenSSL) and DcmSwift,
with the fixtures of Scripts/generate-tls-test-certificates.sh and mutual
authentication.

  tls.py scu PORT FIXTURES  pynetdicom SCU against DcmServer (AE "SCP") started
                            with --tls-certificate, --tls-key, --tls-client-ca:
                            TLS 1.3, TLS 1.2 per allowed suite, refused suites.
  tls.py scp PORT FIXTURES  pynetdicom SCP (AE "PYSCP") requiring a client
                            certificate, for DcmEcho --tls.
"""
import os, ssl, sys
from pynetdicom import AE
from pynetdicom.sop_class import Verification

mode, port, fixtures = sys.argv[1], int(sys.argv[2]), sys.argv[3]
f = lambda name: os.path.join(fixtures, name)

def check(cond, message):
    if not cond:
        print('FAIL', message, flush=True); sys.exit(1)

if mode == 'scu':
    def echo(version=None, ciphers=None, certificate=True):
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=f('tls-ca.pem'))
        if certificate:
            context.load_cert_chain(f('tls-client.pem'), f('tls-client-key.pem'))
        if version:
            context.minimum_version = context.maximum_version = version
        if ciphers:
            context.set_ciphers(ciphers)
        ae = AE(ae_title='PYSCU')
        ae.add_requested_context(Verification)
        assoc = ae.associate('127.0.0.1', port, ae_title='SCP', tls_args=(context, '127.0.0.1'))
        if not assoc.is_established:
            return None
        sock = assoc.dul.socket.socket
        negotiated = (sock.version(), sock.cipher()[0])
        status = assoc.send_c_echo()
        assoc.release()
        return negotiated if status and status.Status == 0 else None
    result = echo()
    check(result and result[0] == 'TLSv1.3', 'TLS 1.3: %s' % (result,))
    print('TLS 1.3', result[1])
    for cipher in ['ECDHE-ECDSA-AES256-GCM-SHA384', 'ECDHE-ECDSA-AES128-GCM-SHA256', 'ECDHE-ECDSA-CHACHA20-POLY1305']:
        result = echo(ssl.TLSVersion.TLSv1_2, cipher)
        check(result == ('TLSv1.2', cipher), 'TLS 1.2 %s: %s' % (cipher, result))
        print('TLS 1.2', cipher)
    for cipher in ['ECDHE-ECDSA-AES128-SHA', 'ECDHE-ECDSA-AES256-SHA384']:
        check(echo(ssl.TLSVersion.TLSv1_2, cipher) is None, 'refused suite %s accepted' % cipher)
    check(echo(certificate=False) is None, 'client without certificate accepted')
    print('OK')
else:
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH, cafile=f('tls-ca.pem'))
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(f('tls-server.pem'), f('tls-server-key.pem'))
    ae = AE(ae_title='PYSCP')
    ae.add_supported_context(Verification)
    ae.start_server(('127.0.0.1', port), block=False, ssl_context=context)
    print('READY', flush=True)
    sys.stdin.read()
