#!/usr/bin/env python3
"""Fills the App Store page of Sunplot through the App Store Connect API.

  ASC_KEY_ID=… ASC_ISSUER_ID=… python3 Tools/asc-listing.py [--version 1.1] [--skip-screenshots]

Sets, for all fifteen store locales: name, subtitle, privacy policy URL, description,
keywords, promotional text, what's new and support URL (texts live in store/listing.py),
plus the screenshots from screenshots/6.1/<language>/; and once per app the categories,
the age rating questionnaire (nothing applies, 4+) and the copyright line.

With --version it creates that App Store version if the app has no editable one.

Safe to re-run: texts are overwritten with the current ones, and a screenshot set that
already holds the same six processed shots is left alone.

🔴 One screenshot size, and it changed: App Store Connect now wants an "iPhone with Dynamic
Island (medium display)" — 1206x2622 from an iPhone 17 — in the slot `APP_IPHONE_61`. Sets
in older slots are deleted here, because a draft that still carries them is refused with
"screenshots do not meet requirements".

🔴 The in-app purchase is deliberately not touched. It is approved and live; editing its
localisations would open a new purchase version that App Review has to pass again, and two
rejections in this app have already come from purchase metadata.

Not possible through the API, so left to the owner: App Privacy ("Data Not Collected").
"""
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "store"))
sys.path.insert(0, str(ROOT / "Tools"))
import asc  # noqa: E402
from listing import LISTING, SCREENSHOTS, check  # noqa: E402

BUNDLE_ID = "app.sunplot"
COPYRIGHT = "2026 Olexandr Zhovnir"
DISPLAY_TYPE = "APP_IPHONE_61"  # iPhone with Dynamic Island, medium display: 1206x2622
SHOTS = ROOT / "screenshots" / "6.1"
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")


def ref(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def log(message):
    print(message, flush=True)


def app_id():
    apps = asc.request("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No app record for {BUNDLE_ID}.")
    return apps[0]["id"]


def editable_app_info(app):
    infos, _ = asc.get_all(f"/v1/apps/{app}/appInfos")
    for info in infos:
        if info["attributes"].get("appStoreState") != "READY_FOR_SALE":
            return info["id"]
    return infos[0]["id"]


def editable_version(app, wanted=None):
    versions, _ = asc.get_all(f"/v1/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})
    for version in versions:
        if version["attributes"].get("appStoreState") in EDITABLE:
            log(f"version {version['attributes']['versionString']}: {version['attributes']['appStoreState']}")
            return version["id"]
    if not wanted:
        sys.exit("No editable App Store version. Pass --version 1.1 to create one.")
    created = asc.request("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": wanted, "releaseType": "MANUAL"},
        "relationships": {"app": ref("apps", app)}}})["data"]
    log(f"version {wanted}: created, release MANUAL")
    return created["id"]


def set_categories(info):
    log("categories: Utilities, Lifestyle")
    asc.request("PATCH", f"/v1/appInfos/{info}", {"data": {
        "type": "appInfos", "id": info,
        "relationships": {"primaryCategory": ref("appCategories", "UTILITIES"),
                          "secondaryCategory": ref("appCategories", "LIFESTYLE")}}})


def set_info_localizations(info):
    existing, _ = asc.get_all(f"/v1/appInfos/{info}/appInfoLocalizations")
    by_locale = {item["attributes"]["locale"]: item["id"] for item in existing}
    for locale, fields in LISTING.items():
        attributes = {"name": fields["name"], "subtitle": fields["subtitle"], "privacyPolicyUrl": fields["privacy"]}
        if locale in by_locale:
            asc.request("PATCH", f"/v1/appInfoLocalizations/{by_locale[locale]}",
                        {"data": {"type": "appInfoLocalizations", "id": by_locale[locale], "attributes": attributes}})
        else:
            asc.request("POST", "/v1/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations", "attributes": {"locale": locale, **attributes},
                "relationships": {"appInfo": ref("appInfos", info)}}})
    log(f"app info: {len(LISTING)} locales")


# The age rating form, answered for an app with none of this content (rated 4+).
# Content questions take a frequency; the newer yes/no questions take a boolean.
AGE_RATING_FREQUENCY = [
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
    "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
]
AGE_RATING_YES_NO = [
    "advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
    "parentalControls", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent",
]


def set_age_rating(info):
    declaration = asc.request("GET", f"/v1/appInfos/{info}/ageRatingDeclaration")["data"]
    present = declaration["attributes"]
    attributes = {key: "NONE" for key in AGE_RATING_FREQUENCY if key in present}
    attributes.update({key: False for key in AGE_RATING_YES_NO if key in present})
    unknown = sorted(set(present) - set(attributes) - {"kidsAgeBand", "developerAgeRatingInfoUrl", "ageRatingOverride",
                                                       "ageRatingOverrideV2", "koreaAgeRatingOverride",
                                                       "gracRatingClassificationNumber"})
    if unknown:
        sys.exit(f"age rating: new questions to answer by hand first: {unknown}")
    log(f"age rating: {len(attributes)} answers, none of it applies")
    asc.request("PATCH", f"/v1/ageRatingDeclarations/{declaration['id']}",
                {"data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": attributes}})


def set_version(version):
    log(f"copyright: {COPYRIGHT}")
    asc.request("PATCH", f"/v1/appStoreVersions/{version}",
                {"data": {"type": "appStoreVersions", "id": version, "attributes": {"copyright": COPYRIGHT}}})
    existing, _ = asc.get_all(f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")
    by_locale = {item["attributes"]["locale"]: item["id"] for item in existing}
    for locale, fields in LISTING.items():
        attributes = {"description": fields["description"], "keywords": fields["keywords"],
                      "promotionalText": fields["promotionalText"], "whatsNew": fields["whatsNew"],
                      "supportUrl": fields["support"]}
        if locale in by_locale:
            asc.request("PATCH", f"/v1/appStoreVersionLocalizations/{by_locale[locale]}",
                        {"data": {"type": "appStoreVersionLocalizations", "id": by_locale[locale],
                                  "attributes": attributes}})
        else:
            created = asc.request("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **attributes},
                "relationships": {"appStoreVersion": ref("appStoreVersions", version)}}})
            by_locale[locale] = created["data"]["id"]
    log(f"version texts: {len(LISTING)} locales")
    return by_locale


def upload_screenshots(localization, folder):
    sets, _ = asc.get_all(f"/v1/appStoreVersionLocalizations/{localization}/appScreenshotSets")
    screenshot_set = None
    for item in sets:
        if item["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            screenshot_set = item["id"]
        else:
            # A set in a size Apple no longer accepts blocks the whole draft.
            asc.request("DELETE", f"/v1/appScreenshotSets/{item['id']}")
            log(f"  removed the old {item['attributes']['screenshotDisplayType']} set")
    if screenshot_set is None:
        screenshot_set = asc.request("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
            "relationships": {
                "appStoreVersionLocalization": ref("appStoreVersionLocalizations", localization)}}})["data"]["id"]
    files = sorted((SHOTS / folder).glob("*.png"))
    if not files:
        sys.exit(f"no screenshots in {(SHOTS / folder).relative_to(ROOT)}: run Tools/shots.py")
    current, _ = asc.get_all(f"/v1/appScreenshotSets/{screenshot_set}/appScreenshots")
    done = [item for item in current if (item["attributes"].get("assetDeliveryState") or {}).get("state") == "COMPLETE"]
    if len(done) == len(files) == len(current):
        return 0
    for item in current:
        asc.request("DELETE", f"/v1/appScreenshots/{item['id']}")
    for path in files:
        content = path.read_bytes()
        reservation = asc.request("POST", "/v1/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(content)},
            "relationships": {"appScreenshotSet": ref("appScreenshotSets", screenshot_set)}}})
        asc.upload_asset(reservation, path)
        asc.request("PATCH", f"/v1/appScreenshots/{reservation['data']['id']}", {"data": {
            "type": "appScreenshots", "id": reservation["data"]["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(content).hexdigest()}}})
    return len(files)


def main():
    problems = check()
    if problems:
        sys.exit("store/listing.py: " + "; ".join(problems))
    wanted = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else None
    app = app_id()
    # The version comes first: while the app is live its only app info is the published one,
    # and App Store Connect opens an editable copy only once a new version exists.
    version = editable_version(app, wanted)
    info = editable_app_info(app)
    set_categories(info)
    set_info_localizations(info)
    set_age_rating(info)
    localizations = set_version(version)
    if "--skip-screenshots" not in sys.argv:
        for locale, folder in SCREENSHOTS.items():
            count = upload_screenshots(localizations[locale], folder)
            log(f"screenshots {locale}: {'uploaded ' + str(count) if count else 'already there'}")
    log("done")


if __name__ == "__main__":
    try:
        main()
    except asc.APIError as error:
        sys.exit(str(error))
