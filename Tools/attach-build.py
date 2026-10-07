#!/usr/bin/env python3
"""Waits for the uploaded build to finish processing and attaches it to the editable version.

    ASC_KEY_ID=… ASC_ISSUER_ID=… python3 Tools/attach-build.py [--minutes 45]

Apple needs a few minutes to process an upload; until then the build does not exist for the
API. Once it is VALID this attaches it to the version being prepared, which is the one thing
between "uploaded" and "ready to submit" that the API can do.

🔴 A build belongs to the version string it was uploaded under, and Apple refuses it on any
other one with a flat 409. Waiting for "the newest valid build" is not enough: right after an
upload the newest build can still be the previous version's — so the wait filters by the
version string being prepared.
"""
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import asc  # noqa: E402

BUNDLE_ID = "app.sunplot"
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")


def main():
    minutes = int(sys.argv[sys.argv.index("--minutes") + 1]) if "--minutes" in sys.argv else 45
    app = asc.request("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]
    versions, _ = asc.get_all(f"/v1/apps/{app['id']}/appStoreVersions", params={"filter[platform]": "IOS"})
    version = next(v for v in versions if v["attributes"]["appStoreState"] in EDITABLE)
    wanted = version["attributes"]["versionString"]
    print(f"{app['attributes']['name']} {wanted}: {version['attributes']['appStoreState']}", flush=True)

    deadline = time.time() + minutes * 60
    while True:
        builds, _ = asc.get_all("/v1/builds", params={
            "filter[app]": app["id"], "sort": "-uploadedDate", "limit": 10,
            "fields[builds]": "version,processingState,uploadedDate",
            "filter[preReleaseVersion.version]": wanted})
        ready = [b for b in builds if b["attributes"]["processingState"] == "VALID"]
        if ready:
            build = ready[0]
            break
        states = ", ".join(f"{b['attributes']['version']}: {b['attributes']['processingState']}" for b in builds)
        print(f"  processing… {states or 'no build under ' + wanted + ' yet'}", flush=True)
        if time.time() > deadline:
            sys.exit("the build never finished processing")
        time.sleep(60)

    asc.request("PATCH", f"/v1/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"],
        "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    print(f"attached build {wanted} ({build['attributes']['version']})")


if __name__ == "__main__":
    try:
        main()
    except asc.APIError as error:
        sys.exit(str(error))
