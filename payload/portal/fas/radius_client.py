"""Minimal PAP auth + accounting client against a local FreeRADIUS server, using pyrad."""

from pyrad.client import Client
from pyrad.dictionary import Dictionary
import pyrad.packet

DICT_PATHS = ["/etc/portal/fas/dictionary"]


def _load_dictionary():
    for path in DICT_PATHS:
        try:
            return Dictionary(path)
        except FileNotFoundError:
            continue
    return Dictionary()


def radius_pap_auth(username, password, server, secret, nas_identifier="opennds-fas", timeout=5):
    if not username or not password:
        return False

    client = Client(server=server, secret=secret.encode("utf-8"), dict=_load_dictionary())
    client.timeout = timeout

    req = client.CreateAuthPacket(code=pyrad.packet.AccessRequest, User_Name=username)
    req["User-Password"] = req.PwCrypt(password)
    req["NAS-Identifier"] = nas_identifier

    try:
        reply = client.SendPacket(req)
    except Exception:
        return False

    return reply.code == pyrad.packet.AccessAccept


def radius_acct_start(username, session_id, clientip, clientmac, server, secret,
                       nas_identifier="opennds-fas", timeout=5):
    """Send an Accounting-Start packet. Failures are swallowed - accounting
    should never block a login the person already succeeded at."""
    try:
        client = Client(server=server, secret=secret.encode("utf-8"), dict=_load_dictionary())
        client.timeout = timeout
        req = client.CreateAcctPacket(User_Name=username)
        req["Acct-Status-Type"] = 1  # Start
        req["Acct-Session-Id"] = session_id
        req["Calling-Station-Id"] = clientmac
        if clientip:
            req["Framed-IP-Address"] = clientip
        req["NAS-Identifier"] = nas_identifier
        client.SendPacket(req)
        return True
    except Exception:
        return False
