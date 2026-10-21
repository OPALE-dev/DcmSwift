"""UPS-RS independent HTTP/WebSocket + DIMSE loopback peer.

python ups_rs.py http://127.0.0.1:21126/dicomweb 21124
Requires websockets, pydicom, pynetdicom. DcmServer must use --aet UPSSCP,
--ups-directory, --http-port, and --http-base-path /dicomweb.
"""
import json
import sys
import urllib.error
import urllib.request
import uuid

from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosedError
from pynetdicom import AE
from pynetdicom.sop_class import UnifiedProcedureStepPush, UnifiedProcedureStepPull
from pydicom.dataset import Dataset


def value(vr, text):
    return {"vr": vr, "Value": [text]}


def scheduled(priority="MEDIUM"):
    result = {"00741200": value("CS", priority), "00741204": value("LO", "Read"),
              "00404005": value("DT", "20261021190000+0200"), "00404041": value("CS", "READY"),
              "00741000": value("CS", "SCHEDULED")}
    for tag, vr in [("00081195", "UI"), ("00741202", "LO"), ("00400400", "LT"), ("00100010", "PN"),
                    ("00100021", "LO"), ("00100030", "DA"), ("00100040", "CS"), ("00380010", "LO"), ("00081080", "LO")]:
        result[tag] = {"vr": vr}
    for tag in ["00741210", "00404025", "00404026", "00404027", "00404018", "00404021", "00100024",
                "00101002", "00380014", "00081084", "0040A370", "00741002", "00741216"]:
        result[tag] = {"vr": "SQ"}
    return result


def main(base, dimse_port):
    uid = "2.25." + str(uuid.uuid4().int)
    token = "2.25." + str(uuid.uuid4().int)
    item = "/workitems/" + uid
    subscriber = item + "/subscribers/WEBWATCH"

    def http(method, path, expected, obj=None, accept=None, raw=None, content_type=None):
        headers = {}
        body = raw
        if obj is not None:
            body = json.dumps([obj]).encode()
            headers["Content-Type"] = "application/dicom+json"
        if content_type:
            headers["Content-Type"] = content_type
        if accept:
            headers["Accept"] = accept
        request = urllib.request.Request(base + path, data=body, method=method, headers=headers)
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read()
            assert response.status == expected, (method, path, response.status, data)
            print("OK", method, path, expected, flush=True)
            return data, response.headers

    ws_url = base.replace("https://", "wss://").replace("http://", "ws://") + "/subscribers/WEBWATCH"

    def event(socket, kind, target=uid):
        obj = json.loads(socket.recv(timeout=5))
        assert obj["00001002"]["Value"] == [kind], obj
        assert obj["00001000"]["Value"] == [target], obj
        assert obj["00000002"]["Value"] == [str("1.2.840.10008.5.1.4.34.6.4")], obj
        assert "00081195" not in obj, obj
        print("OK WebSocket event", kind, flush=True)
        return obj

    http("POST", "/workitems?workitem=" + uid, 201, scheduled())
    http("POST", "/workitems?workitem=" + uid, 409, scheduled())
    with connect(ws_url, origin=base, subprotocols=["dicom"], open_timeout=10) as socket:
        _, headers = http("POST", subscriber + "?deletionlock=true", 201)
        assert headers["Content-Location"] == ws_url
        event(socket, 1)
        code = {"00080100": value("SH", "STATION"), "00080102": value("SH", "99TEST"), "00080104": value("LO", "Station")}
        http("POST", item, 200, {"00404025": {"vr": "SQ", "Value": [code]}})
        event(socket, 5)
        assert socket.ping(b"UPS").wait(timeout=5), "missing pong"
        print("OK ping/pong", flush=True)
        ae = AE(ae_title="UPSSCU")
        ae.add_requested_context(UnifiedProcedureStepPush)
        ae.add_requested_context(UnifiedProcedureStepPull)
        association = ae.associate("127.0.0.1", dimse_port, ae_title="UPSSCP")
        assert association.is_established
        try:
            status, data = association.send_n_get([0x00741000], UnifiedProcedureStepPush, uid)
            assert status.Status == 0 and data.ProcedureStepState == "SCHEDULED"
            print("OK HTTP-created instance visible over DIMSE", flush=True)
            action = Dataset()
            action.ProcedureStepState = "IN PROGRESS"
            action.TransactionUID = token
            status, _ = association.send_n_action(action, 1, UnifiedProcedureStepPush, uid, meta_uid=UnifiedProcedureStepPull)
            assert status.Status == 0
            event(socket, 1)
        finally:
            association.release()
        http("POST", item + "?transactionuid=2.25.999", 400, {"00404041": value("CS", "UNAVAILABLE")})
        http("POST", item + "?transactionuid=" + token, 200, {"00404041": value("CS", "UNAVAILABLE")})
        event(socket, 1)
        http("PUT", item + "/state", 409, {"00741000": value("CS", "COMPLETED"), "00081195": value("UI", token)})
        data, _ = http("GET", item, 200)
        assert "00081195" not in json.loads(data)[0]
        http("POST", item + "/cancelrequest?requester=REMOTE", 202, {"00741238": value("LT", "Stop")})
        cancel = event(socket, 2)
        assert cancel["00741236"]["Value"] == ["REMOTE"]
    print("OK close handshake", flush=True)
    # The persistent subscription and deletion lock survive reconnection.
    with connect(ws_url, origin=base, subprotocols=["dicom"], open_timeout=10) as socket:
        code = {"00080100": value("SH", "110513"), "00080102": value("SH", "DCM"),
                "00080104": value("LO", "Discontinued")}
        progress = {"vr": "SQ", "Value": [{"0074100E": {"vr": "SQ", "Value": [code]}}]}
        http("POST", item + "?transactionuid=" + token, 200, {"00741002": progress})
        event(socket, 3)
        final = {"00741000": value("CS", "CANCELED"), "00081195": value("UI", token)}
        http("PUT", item + "/state", 200, final)
        event(socket, 1)
        _, headers = http("PUT", item + "/state", 200, final)
        assert "already" in headers["Warning"]
        print("OK persistent subscription resumes without resubscribe", flush=True)
        xml, headers = http("GET", item, 200, accept='multipart/related; type="application/dicom+xml"')
        assert b"NativeDicomModel" in xml and b'tag="00081195"' not in xml
        http("DELETE", subscriber, 200)
        filtered = "/workitems/1.2.840.10008.5.1.4.34.5.1/subscribers/WEBWATCH"
        http("POST", filtered + "?deletionlock=true&filter=ScheduledProcedureStepPriority%3DHIGH", 201)
        uid2 = "2.25." + str(uuid.uuid4().int)
        http("POST", "/workitems?workitem=" + uid2, 201, scheduled("HIGH"))
        event(socket, 1, uid2)
        http("POST", filtered + "/suspend", 200)
        http("DELETE", "/workitems/" + uid2 + "/subscribers/WEBWATCH", 200)
    with connect(ws_url, origin=base, open_timeout=10) as socket:
        socket.socket.sendall(b"\x89\x01X")  # Deliberately unmasked client ping.
        try:
            socket.recv(timeout=5)
            raise AssertionError("unmasked client frame was accepted")
        except ConnectionClosedError as error:
            assert error.rcvd.code == 1002, error
            print("OK unmasked client frame rejected with protocol error", flush=True)
    with connect(ws_url, origin=base, open_timeout=10) as socket:
        socket.send("not a notification client operation")
        try:
            socket.recv(timeout=5)
            raise AssertionError("client application message was accepted")
        except ConnectionClosedError as error:
            assert error.rcvd.code == 1003, error
            print("OK unexpected client message rejected", flush=True)
    http("GET", "/workitems?ProcedureStepState=CANCELED&includefield=all&limit=1", 200)
    data, _ = http("GET", "/workitems?ProcedureStepLabel=NONE", 200)
    assert json.loads(data) == []
    http("GET", item, 406, accept="image/png")
    http("POST", "/workitems", 400, raw=b"{}", content_type="application/dicom+json")
    http("POST", "/workitems", 415, raw=b"text", content_type="text/plain")
    http("GET", "/workitems/2.25.9999999999999", 404)
    capabilities, _ = http("OPTIONS", "", 200)
    assert b"OpenNotificationConnection" in capabilities and b"SearchWorkitems" in capabilities
    print("UPS-RS HTTP/XML/WebSocket/DIMSE interop passed", flush=True)


if __name__ == "__main__":
    main(sys.argv[1].rstrip("/"), int(sys.argv[2]))
