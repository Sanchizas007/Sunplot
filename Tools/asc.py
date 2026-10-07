#!/usr/bin/env python3
"""Minimal App Store Connect API client.

Needs ASC_KEY_ID and ASC_ISSUER_ID in the environment and the matching .p8 in
~/.appstoreconnect/private_keys/ (same setup altool uses). Tokens come from
Tools/asc-token.swift, compiled into build/ on first use.

  python3 Tools/asc.py GET /v1/apps
  python3 Tools/asc.py POST /v1/bundleIds '{"data": {...}}'
"""
import http.client
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TIMEOUT = 90        # a hung request is worse than a failed one: it never comes back
UPLOAD_TIMEOUT = 180
BASE = "https://api.appstoreconnect.apple.com"
_token = {"value": None, "made": 0.0}


class APIError(Exception):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path} -> {status}: {body}")
        self.status = status
        self.body = body


def token():
    if _token["value"] and time.time() - _token["made"] < 900:
        return _token["value"]
    source = ROOT / "Tools" / "asc-token.swift"
    binary = ROOT / "build" / "asc-token"
    if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
        binary.parent.mkdir(exist_ok=True)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
    _token.update(value=result.stdout.strip(), made=time.time())
    return _token["value"]


def request(method, path, body=None, params=None):
    url = path if path.startswith("http") else BASE + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=headers),
                                        timeout=TIMEOUT) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            text = error.read().decode(errors="replace")
            if error.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(2 ** attempt * 2)
                continue
            raise APIError(method, path, error.code, text) from None
        except (OSError, http.client.HTTPException) as error:
            # A request without a timeout can hang for good: an upload of 70 screenshots
            # stopped dead on one of them and sat there until it was killed. OSError covers
            # urllib's URLError and socket.timeout, which on Python 3.9 is not a TimeoutError.
            if attempt < 3:
                time.sleep(2 ** attempt * 2)
                continue
            raise APIError(method, path, "network", str(error)) from None


def get_all(path, params=None):
    """Every item of a paged collection."""
    items, included = [], []
    page = request("GET", path, params=params)
    while True:
        items += page.get("data", [])
        included += page.get("included", [])
        next_url = page.get("links", {}).get("next")
        if not next_url:
            return items, included
        page = request("GET", next_url)


def upload_asset(reservation, file_path):
    """Sends a file to the upload operations App Store Connect handed out for an asset."""
    content = pathlib.Path(file_path).read_bytes()
    for operation in reservation["data"]["attributes"]["uploadOperations"]:
        chunk = content[operation["offset"]:operation["offset"] + operation["length"]]
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
        upload = urllib.request.Request(operation["url"], data=chunk, method=operation["method"], headers=headers)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(upload, timeout=UPLOAD_TIMEOUT) as response:
                    response.read()
                break
            except (OSError, http.client.HTTPException) as error:
                if attempt == 3:
                    raise APIError(operation["method"], operation["url"][:60], "upload", str(error)) from None
                time.sleep(2 ** attempt * 2)


def main():
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    try:
        print(json.dumps(request(method, path, body), indent=2, ensure_ascii=False))
    except APIError as error:
        print(error, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
