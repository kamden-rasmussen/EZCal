#!/usr/bin/env python3
"""Adds an uploaded build to the external TestFlight group and submits it for beta app review.

Usage: scripts/ios_testflight_distribute.py <build number>
Env: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (App Store Connect API key), GROUP (default "Testing"),
     APP_ID (default 6829086317), WAIT (seconds to wait for processing; default 1800).
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request

APP_ID = os.environ.get("APP_ID", "6829086317")
GROUP = os.environ.get("GROUP", "Testing")
WAIT = int(os.environ.get("WAIT", "1800"))
API = "https://api.appstoreconnect.apple.com"


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw(der):
    # openssl emits an ASN.1 DER ECDSA signature; JWT ES256 wants r || s as 32 bytes each.
    assert der[0] == 0x30
    i = 2 + (der[1] - 0x80 if der[1] & 0x80 else 0)
    parts = []
    for _ in range(2):
        n = der[i + 1]
        parts.append(der[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0"))
        i += 2 + n
    return b"".join(parts)


def token():
    key, kid, iss = (os.environ[k] for k in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"))
    head = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": iss, "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"}).encode())
    msg = head + b"." + body
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=msg, capture_output=True, check=True).stdout
    return (msg + b"." + b64(der_to_raw(sig))).decode()


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method, data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        raw = urllib.request.urlopen(req).read()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} failed: {e.read().decode()}")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    build = sys.argv[1]
    deadline = time.time() + WAIT
    while True:
        found = call("GET", f"/v1/builds?filter[app]={APP_ID}&filter[version]={build}&fields[builds]=processingState").get("data", [])
        state = found[0]["attributes"]["processingState"] if found else "NOT_YET_VISIBLE"
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            raise SystemExit(f"Build {build} processing {state}")
        if time.time() > deadline:
            raise SystemExit(f"Build {build} still {state} after {WAIT}s; rerun this script later")
        print(f"Build {build}: {state}, waiting...")
        time.sleep(30)
    build_id = found[0]["id"]

    groups = call("GET", f"/v1/apps/{APP_ID}/betaGroups?limit=200").get("data", [])
    groups = [g for g in groups if g["attributes"]["name"] == GROUP]
    if not groups:
        raise SystemExit(f'TestFlight group "{GROUP}" not found')
    call("POST", f"/v1/betaGroups/{groups[0]['id']}/relationships/builds", {"data": [{"type": "builds", "id": build_id}]})
    print(f'Added build {build} to group "{GROUP}"')

    req = urllib.request.Request(
        API + "/v1/betaAppReviewSubmissions", method="POST",
        data=json.dumps({"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}).encode(),
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req)
        print(f"Submitted build {build} for beta app review")
    except urllib.error.HTTPError as e:
        # Another build in the same train being in review is normal; resubmit once it finishes.
        print(f"Beta review not submitted (build is in the group): {e.read().decode()}")


main()
