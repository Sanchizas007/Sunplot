#!/usr/bin/env python3
"""Puts store/review-notes.txt into the App Review notes of the editable version.

    ASC_KEY_ID=… ASC_ISSUER_ID=… python3 Tools/asc-review-notes.py

The notes live on the version, not on the app, and a new version starts from the previous
one's — which is how a paragraph written for one review (the screen recording App Review asked
for in September) was still there a month later. The field holds 4000 characters and a longer
text is cut silently by the web page, so the length is checked here first.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Tools"))
import asc  # noqa: E402

BUNDLE_ID = "app.sunplot"
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")


def main():
    notes = (ROOT / "store" / "review-notes.txt").read_text(encoding="utf-8").rstrip("\n")
    if len(notes) > 4000:
        sys.exit(f"the notes are {len(notes)} characters; the field holds 4000")
    app = asc.request("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]["id"]
    versions, _ = asc.get_all(f"/v1/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})
    version = next(v for v in versions if v["attributes"]["appStoreState"] in EDITABLE)

    detail = asc.request("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    if detail:
        asc.request("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
    else:
        asc.request("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": {"notes": notes},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    saved = asc.request("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]["attributes"]["notes"]
    print(f"version {version['attributes']['versionString']}: notes saved, {len(saved)} characters,",
          "starts with", repr(saved[:24]))


if __name__ == "__main__":
    try:
        main()
    except asc.APIError as error:
        sys.exit(str(error))
