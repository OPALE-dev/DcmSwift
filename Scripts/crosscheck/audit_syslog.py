"""Check DcmServer's audit messages end to end against PS3.15 A.5 to A.7.

  audit_syslog.py part15.xml BUILD_DIR FILE.dcm

BUILD_DIR holds DcmServer, DcmStore, DcmFind, and DcmEcho. Needs rnc2rng,
lxml, syslog-rfc5424-parser, and pynetdicom (pip install), and openssl.

A syslog collector listens over TLS (RFC 5425) and UDP (RFC 5426); DcmServer
sends its audit messages to both. FILE.dcm is stored with DcmStore, queried
with DcmFind and QIDO-RS, retrieved with C-GET (pynetdicom) and WADO-RS, and
an association from an AE title that is not allowed is rejected. Every
syslog message received is parsed by syslog-rfc5424-parser and checked:
PRI 85 (facility 10, severity 5), MSGID DICOM+RFC3881, and a MSG that the
DICOM Audit Message Schema of PS3.15 A.5.1, read from the DocBook, accepts.
The events expected are checked with the participants and objects A.5.3
requires. Exits 1 on any failure.
"""
import json
import os
import re
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

import rnc2rng
from lxml import etree
from pydicom import dcmread
from pynetdicom import AE, evt, build_role
from pynetdicom.sop_class import StudyRootQueryRetrieveInformationModelGet
from syslog_rfc5424_parser import SyslogMessage

DCM = {"110100": "Application Activity", "110104": "DICOM Instances Transferred", "110112": "Query",
       "110102": "Begin Transferring DICOM Instances", "110113": "Security Alert"}


def schema_from(part15):
    text = open(part15, encoding="utf-8").read()
    start = text.index('xml:id="sect_A.5.1.1"')
    rnc = re.search(r"<!\[CDATA\[(.*?)\]\]>", text[start:], re.S).group(1)
    # rnc2rng does not take documentation comments everywhere.
    with tempfile.NamedTemporaryFile("w", suffix=".rnc", delete=False) as file:
        file.write(rnc.replace("##", "#"))
    return etree.RelaxNG(etree.fromstring(rnc2rng.dumps(rnc2rng.load(file.name)).encode()))


class Collector:
    """Syslog over TLS (octet counting) and UDP."""

    def __init__(self, folder):
        self.messages = {"tls": [], "udp": []}
        certificate, key = os.path.join(folder, "collector.pem"), os.path.join(folder, "collector.key")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                        "-nodes", "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1",
                        "-keyout", key, "-out", certificate], check=True, capture_output=True)
        self.certificate = certificate
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(certificate, key)
        self.tls = socket.socket()
        self.tls.bind(("127.0.0.1", 0))
        self.tls.listen()
        self.tls_port = self.tls.getsockname()[1]
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(("127.0.0.1", 0))
        self.udp_port = self.udp.getsockname()[1]
        threading.Thread(target=self.accept, args=(context,), daemon=True).start()
        threading.Thread(target=self.receive, daemon=True).start()

    def accept(self, context):
        while True:
            connection, _ = self.tls.accept()
            threading.Thread(target=self.read, args=(context.wrap_socket(connection, server_side=True),),
                             daemon=True).start()

    def read(self, connection):
        buffer = b""
        while True:
            data = connection.recv(65536)
            if not data:
                return
            buffer += data
            # MSG-LEN SP SYSLOG-MSG (RFC 5425 4.3).
            while b" " in buffer:
                length, rest = buffer.split(b" ", 1)
                if len(rest) < int(length):
                    break
                self.messages["tls"].append(rest[:int(length)])
                buffer = rest[int(length):]

    def receive(self):
        while True:
            self.messages["udp"].append(self.udp.recvfrom(65535)[0])


def check(raw, schema, failures):
    """The syslog message and its audit message; returns the XML root."""
    if not raw.split(b" - ", 1)[-1].startswith(b"\xef\xbb\xbf"):
        failures.append("MSG without the UTF-8 byte order mark")
    message = SyslogMessage.parse(raw.decode("utf-8"))
    if message.facility.value != 10 or message.severity.value != 5:
        failures.append(f"PRI facility {message.facility}, severity {message.severity}")
    if message.msgid != "DICOM+RFC3881" or message.version != 1:
        failures.append(f"MSGID {message.msgid}, VERSION {message.version}")
    xml = message.msg.lstrip("﻿").encode("utf-8")
    root = etree.fromstring(xml)
    if not schema.validate(root):
        failures.append(f"schema: {schema.error_log.last_error}")
    return root


def roles(root):
    return [[code.get("csd-code") for code in participant.findall("RoleIDCode")]
            for participant in root.findall("ActiveParticipant")]


def main(part15, build, file):
    schema = schema_from(part15)
    failures = []
    with tempfile.TemporaryDirectory() as folder:
        collector = Collector(folder)
        storage = os.path.join(folder, "storage")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            http_port = probe.getsockname()[1]
        server = subprocess.Popen(
            [os.path.join(build, "DcmServer"), "--aet", "ARCHIVE", "--host", "127.0.0.1", "--port", str(port),
             "--storage-directory", storage, "--http-port", str(http_port), "--allow-calling-aet", "STORESCU",
             "--audit", f"tls://127.0.0.1:{collector.tls_port}", "--audit", f"udp://127.0.0.1:{collector.udp_port}",
             "--audit-tls-ca", collector.certificate], stdout=subprocess.PIPE, text=True)
        while "listening" not in (server.stdout.readline() or "listening"):
            pass
        try:
            # Keep reading the server's output, which would otherwise block it.
            threading.Thread(target=lambda: [None for _ in server.stdout], daemon=True).start()
            time.sleep(1)
            tool = lambda name, *arguments: subprocess.run(
                [os.path.join(build, name), *arguments], capture_output=True, text=True, timeout=60)
            tool("DcmStore", "-c", "STORESCU", "ARCHIVE", "127.0.0.1", str(port), file)
            tool("DcmFind", "-c", "STORESCU", "-k", "PatientID", "ARCHIVE", "127.0.0.1", str(port))
            tool("DcmEcho", "-c", "INTRUDER", "ARCHIVE", "127.0.0.1", str(port))
            study = dcmread(file).StudyInstanceUID
            # PS3.18 8.7.5: a request without Accept gets 406.
            urllib.request.urlopen(urllib.request.Request(
                f"http://127.0.0.1:{http_port}/dicomweb/studies?StudyInstanceUID={study}",
                headers={"Accept": "application/dicom+json"}), timeout=60).read()
            urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{http_port}/dicomweb/studies/{study}",
                                                          headers={"Accept": "multipart/related; type=\"application/dicom\""}),
                                   timeout=60).read()
            # C-GET with pynetdicom.
            ae = AE(ae_title="STORESCU")
            ae.add_requested_context(StudyRootQueryRetrieveInformationModelGet)
            sop_class = dcmread(file).SOPClassUID
            ae.add_requested_context(sop_class)
            association = ae.associate("127.0.0.1", port, ae_title="ARCHIVE", ext_neg=[build_role(sop_class, scp_role=True)],
                                       evt_handlers=[(evt.EVT_C_STORE, lambda event: 0x0000)])
            identifier = dcmread(file, specific_tags=["StudyInstanceUID"])
            identifier.QueryRetrieveLevel = "STUDY"
            for _ in association.send_c_get(identifier, StudyRootQueryRetrieveInformationModelGet):
                pass
            association.release()
        finally:
            if server.poll() is None:
                server.send_signal(signal.SIGTERM)
                try:
                    server.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    server.kill()
                    failures.append("DcmServer did not stop on SIGTERM")
        time.sleep(1)

        received = {}
        for transport in ("tls", "udp"):
            events = []
            for raw in collector.messages[transport]:
                root = check(raw, schema, failures)
                identification = root.find("EventIdentification")
                event = identification.find("EventID").get("csd-code")
                types = [code.get("csd-code") for code in identification.findall("EventTypeCode")]
                events.append((event, identification.get("EventActionCode"), tuple(types), root))
            received[transport] = events
            print(f"{transport}: {len(events)} messages: "
                  + ", ".join(f"{DCM.get(e, e)} {a or ''}{list(t) if t else ''}" for e, a, t, _ in events))
        if [e[:3] for e in received["tls"]] != [e[:3] for e in received["udp"]]:
            failures.append("TLS and UDP received different messages")

        events = received["tls"]
        def find(event, action=None, types=()):
            return [root for e, a, t, root in events if e == event and (action is None or a == action)
                    and all(code in t for code in types)]
        expected = [("110100", "E", ("110120",)), ("110100", "E", ("110121",)), ("110104", "C", ()),
                    ("110112", "E", ()), ("110113", "E", ("110126",)), ("110102", "E", ()), ("110104", "R", ())]
        for event, action, types in expected:
            if not find(event, action, types):
                failures.append(f"missing {DCM[event]} {action} {list(types)}")
        for root in find("110104") + find("110102"):
            if sorted(sum(roles(root), [])) != ["110152", "110153"]:
                failures.append(f"transfer roles {roles(root)}")
            objects = root.findall("ParticipantObjectIdentification")
            types = sorted(o.find("ParticipantObjectIDTypeCode").get("csd-code") for o in objects)
            if types != ["110180", "2"] or study not in [o.get("ParticipantObjectID") for o in objects]:
                failures.append(f"transfer objects {types}")
        for root in find("110112"):
            query = root.find("ParticipantObjectIdentification")
            details = {d.get("type") for d in query.findall("ParticipantObjectDetail")}
            if query.find("ParticipantObjectQuery") is None or "TransferSyntax" not in details:
                failures.append("query without its Data Set or Transfer Syntax")
        for root in find("110113"):
            subject = root.find("ParticipantObjectIdentification")
            if not any(d.get("type") == "Alert Description" for d in subject.findall("ParticipantObjectDetail")):
                failures.append("security alert without an Alert Description")
    for failure in failures:
        print("FAIL", failure)
    print(f"{len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
