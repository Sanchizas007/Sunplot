#!/usr/bin/env python3
"""Sends the editable App Store version to App Review.

    ASC_KEY_ID=… ASC_ISSUER_ID=… python3 Tools/asc-submit.py

Run it only after the owner has said to submit.

The in-app purchase is not added here. It is already approved and live, and a purchase only
needs resubmitting when its own metadata changed — which in this app has twice been the thing
App Review refused, so it is left alone unless something about it actually moves.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import asc  # noqa: E402

BUNDLE_ID = "app.sunplot"


def ref(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def detail(error):
    try:
        return "; ".join(item.get("detail", "") for item in json.loads(error.body)["errors"])
    except (ValueError, KeyError, TypeError):
        return str(error.body)[:300]


def main():
    app = asc.request("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]["id"]
    versions, _ = asc.get_all(f"/v1/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})
    version = next(v for v in versions if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")
    print(f"version {version['attributes']['versionString']} ({version['id']})")

    build = asc.request("GET", f"/v1/appStoreVersions/{version['id']}/build")
    if not build.get("data"):
        sys.exit("no build attached: run Tools/attach-build.py first")
    print(f"build {build['data']['attributes']['version']}")

    drafts, _ = asc.get_all("/v1/reviewSubmissions",
                            params={"filter[app]": app, "filter[state]": "READY_FOR_REVIEW"})
    if drafts:
        submission = drafts[0]["id"]
        print(f"reusing review submission {submission[:8]}")
    else:
        submission = asc.request("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": ref("apps", app)}}})["data"]["id"]
        print(f"review submission {submission[:8]}")

    items, _ = asc.get_all(f"/v1/reviewSubmissions/{submission}/items", params={"include": "appStoreVersion"})
    if not any((item["relationships"].get("appStoreVersion", {}).get("data") or {}).get("id") == version["id"]
               for item in items):
        asc.request("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": ref("reviewSubmissions", submission),
                              "appStoreVersion": ref("appStoreVersions", version["id"])}}})
        print("  + version")

    try:
        asc.request("PATCH", f"/v1/reviewSubmissions/{submission}", {"data": {
            "type": "reviewSubmissions", "id": submission, "attributes": {"submitted": True}}})
    except asc.APIError as error:
        sys.exit(f"submit: {detail(error)}")

    state = asc.request("GET", f"/v1/reviewSubmissions/{submission}")["data"]["attributes"]
    refreshed = asc.request("GET", f"/v1/appStoreVersions/{version['id']}")["data"]["attributes"]
    print(f"\nreview submission: {state.get('state')}")
    print(f"version {refreshed['versionString']}: {refreshed['appStoreState']}, release {refreshed['releaseType']}")
    for purchase in asc.get_all(f"/v1/apps/{app}/inAppPurchasesV2")[0]:
        print(f"{purchase['attributes']['productId']}: {purchase['attributes']['state']}")


if __name__ == "__main__":
    try:
        main()
    except asc.APIError as error:
        sys.exit(str(error))
