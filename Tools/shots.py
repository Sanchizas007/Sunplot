#!/usr/bin/env python3
"""App Store screenshots: six screens × fourteen languages, framed and captioned.

  python3 Tools/shots.py                  build, capture everything, compose
  python3 Tools/shots.py --frame-only     recompose from the captures already taken
  python3 Tools/shots.py --only en,ja     some languages
  python3 Tools/shots.py --review         the paywall for the in-app purchase form (6.5")

Output (git-ignored): `screenshots/6.1/<language>/NN-name.png` ready to upload, and the
untouched captures in `screenshots/raw/`.

The layout follows ASO-Screenshots-TZ.md: a headline at 5–6% of the frame's height, two
lines at most, one subtitle under it, the phone below with its bottom running off the
frame, one colour across the whole set.

🔴 One size only, and it is not the old one. App Store Connect now wants a shot from an
"iPhone with Dynamic Island (medium display)" — 1206x2622 — and refuses a draft that still
carries the 1284x2778 sets. iPhone 17 gives exactly that; the slot in the API is
APP_IPHONE_61.

🔴 The simulator is erased before the run: leftovers from another app reach the frame —
another app's name in the status bar, a 12-hour clock under a German locale.

The screens come from the debug build's demo mode, so every language shows the same garden.
The first caption carries the figure the app itself printed in that language (the app writes
it next to its ready marker), rather than an English number typed into fourteen files.
"""
import json
import math
import pathlib
import random
import subprocess
import sys
import time

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "screenshots"
CAPTIONS = json.loads((ROOT / "Tools" / "screenshots" / "captions.json").read_text())
DERIVED = pathlib.Path("/tmp/sunplot-shots-dd")  # a path without spaces: xcodebuild needs one
APP = DERIVED / "Build/Products/Debug-iphonesimulator/Sunspot.app"
BUNDLE = "app.sunplot"
DEVICE = "iPhone 17"
SIZE = (1206, 2622)
REVIEW_DEVICE = "iPhone 14 Plus"
REVIEW_SIZE = (1284, 2778)

LOCALES = {
    "en": "en_GB", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT", "ja": "ja_JP",
    "ko": "ko_KR", "nl": "nl_NL", "pl": "pl_PL", "pt-BR": "pt_BR", "ru": "ru_RU",
    "tr": "tr_TR", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW",
}
# en_GB rather than en_US on purpose: the status bar then shows a 24-hour clock, the same as
# every other language in the set, and the frames match each other.

SCREENS = [
    ("01-today", "today"),
    ("02-sky", "sky"),
    ("03-year", "year"),
    ("04-plants", "plants"),
    ("05-map", "map"),
    ("06-compare", "compare"),
]

# 🔴 The system font has no CJK glyphs at all: a Japanese caption drawn with it comes out as
# rows of striped boxes. Each script gets a font that carries it, in a weight close to the
# bold the Latin captions use.
FONTS = {
    "ja": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
    "zh-Hans": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
    "zh-Hant": ("/System/Library/Fonts/STHeiti Medium.ttc", 0),  # Heiti TC: traditional shapes
    "ko": ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6),
}
LATIN_FONT = "/System/Library/Fonts/SFNS.ttf"
NO_SPACES = {"ja", "zh-Hans", "zh-Hant"}

# One sky across the whole set, from the deep blue overhead down to the warm band that sits
# over every horizon, with the sun out of frame at the top right and foliage out of focus at
# the bottom — the garden the app is about, without pretending to be a screen of the app.
SKY = [
    (0.00, (18, 112, 206)),
    (0.30, (46, 140, 224)),
    (0.55, (120, 186, 236)),
    (0.72, (196, 214, 226)),
    (0.86, (226, 208, 150)),
    (1.00, (214, 190, 110)),
]


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


# MARK: - the picture


def gradient(width, height):
    image = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        for index in range(len(SKY) - 1):
            start, end = SKY[index], SKY[index + 1]
            if start[0] <= t <= end[0]:
                k = (t - start[0]) / (end[0] - start[0])
                colour = tuple(round(a + (b - a) * k) for a, b in zip(start[1], end[1]))
                break
        draw.line([(0, y), (width, y)], fill=colour)
    return image


def sun_glare(image):
    """A soft flare in the top right corner, drawn rather than photographed."""
    width, height = image.size
    glare = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(glare)
    centre = (width * 0.90, height * 0.045)
    for radius, value in ((width * 0.60, 34), (width * 0.38, 64), (width * 0.22, 120), (width * 0.11, 225)):
        draw.ellipse([centre[0] - radius, centre[1] - radius, centre[0] + radius, centre[1] + radius], fill=value)
    for angle in range(0, 360, 18):  # a few long rays, barely there
        radians = math.radians(angle)
        end = (centre[0] + math.cos(radians) * width * 0.75, centre[1] + math.sin(radians) * width * 0.75)
        draw.line([centre, end], fill=30, width=round(width * 0.013))
    glare = glare.filter(ImageFilter.GaussianBlur(width * 0.035))
    image.paste(Image.new("RGB", (width, height), (255, 248, 214)), (0, 0), glare)
    return image


def foliage(image):
    """Sunlit leaves thrown out of focus along the bottom edge."""
    width, height = image.size
    band_top = round(height * 0.70)
    leaves = Image.new("RGBA", (width, height - band_top), (0, 0, 0, 0))
    draw = ImageDraw.Draw(leaves)
    rng = random.Random(20261007)  # the same garden in every language and every rerun
    for _ in range(260):
        x = rng.uniform(-0.05, 1.05) * width
        depth = rng.random()
        y = (height - band_top) * (0.08 + 0.95 * depth * rng.random())
        radius = width * rng.uniform(0.02, 0.085) * (0.6 + depth)
        green = rng.randint(150, 215)
        colour = (rng.randint(150, 230), green, rng.randint(40, 110), rng.randint(120, 225))
        draw.ellipse([x - radius, y - radius * 0.8, x + radius, y + radius * 0.8], fill=colour)
    leaves = leaves.filter(ImageFilter.GaussianBlur(width * 0.022))
    image.paste(leaves, (0, band_top), leaves)
    return image


def backdrop(width, height):
    return foliage(sun_glare(gradient(width, height)))


def caption_font(language, size):
    if language in FONTS:
        path, index = FONTS[language]
        return ImageFont.truetype(path, size, index=index)
    font = ImageFont.truetype(LATIN_FONT, size)
    font.set_variation_by_name("Bold")
    return font


def body_font(language, size):
    if language in FONTS:
        path, index = FONTS[language]
        return ImageFont.truetype(path, size, index=index)
    font = ImageFont.truetype(LATIN_FONT, size)
    font.set_variation_by_name("Medium")
    return font


def wrap(draw, text, font, width, language):
    """Two lines of similar length where possible, so no word dangles on its own."""
    if draw.textlength(text, font=font) <= width:
        return [text]
    if language in NO_SPACES:
        return wrap_characters(draw, text, font, width)
    words = text.split()
    best = None
    for cut in range(1, len(words)):
        first, second = " ".join(words[:cut]), " ".join(words[cut:])
        longest = max(draw.textlength(first, font=font), draw.textlength(second, font=font))
        # "6h 2m of / direct sun" читается хуже, чем "6h 2m / of direct sun":
        # предлог в конце строки висит.
        score = longest * (2.1 if len(first.split()[-1]) <= 3 else 1)
        if longest <= width and (best is None or score < best[0]):
            best = (score, [first, second])
    if best:
        return best[1]
    lines, line = [], ""
    for word in words:
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=font) <= width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    return lines + [line]


def wrap_characters(draw, text, font, width):
    best = None
    for cut in range(1, len(text)):
        first, second = text[:cut], text[cut:]
        if second[0] in "、，。：":  # punctuation never starts a line
            continue
        longest = max(draw.textlength(first, font=font), draw.textlength(second, font=font))
        if longest <= width and (best is None or longest < best[0]):
            best = (longest, [first, second])
    return best[1] if best else [text]


def phone(canvas, shot, top):
    """The capture inside a drawn iPhone, its bottom running off the frame."""
    width, height = canvas.size
    body_width = round(width * 0.80)
    bezel = round(width * 0.013)
    screen_width = body_width - bezel * 2
    scale = screen_width / shot.width
    screen_height = round(shot.height * scale)
    left = (width - body_width) // 2
    radius = round(body_width * 0.125)

    shadow = Image.new("L", (width, height), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left, top + round(height * 0.012), left + body_width, top + screen_height + bezel * 2 + round(height * 0.012)],
        radius=radius, fill=120)
    canvas.paste(Image.new("RGB", (width, height), (10, 40, 86)),
                 (0, 0), shadow.filter(ImageFilter.GaussianBlur(width * 0.028)))

    body = Image.new("RGBA", (body_width, screen_height + bezel * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle([0, 0, body_width - 1, body.height - 1], radius=radius, fill=(26, 27, 30, 255))
    draw.rounded_rectangle([0, 0, body_width - 1, body.height - 1], radius=radius,
                           outline=(92, 96, 104, 255), width=max(2, round(width * 0.0022)))
    # Side buttons, the only detail that reads at this size.
    button = (58, 60, 66, 255)
    draw.rounded_rectangle([-2, round(body.height * 0.17), 3, round(body.height * 0.215)], radius=3, fill=button)
    draw.rounded_rectangle([-2, round(body.height * 0.245), 3, round(body.height * 0.315)], radius=3, fill=button)
    draw.rounded_rectangle([-2, round(body.height * 0.335), 3, round(body.height * 0.405)], radius=3, fill=button)
    draw.rounded_rectangle([body_width - 4, round(body.height * 0.27), body_width + 1,
                            round(body.height * 0.38)], radius=3, fill=button)

    mask = Image.new("L", (screen_width, screen_height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen_width - 1, screen_height - 1],
                                           radius=radius - bezel, fill=255)
    body.paste(shot.resize((screen_width, screen_height), Image.LANCZOS), (bezel, bezel), mask)
    canvas.paste(body, (left, top), body)
    return canvas


def compose(raw_path, title, subtitle, out_path, language):
    shot = Image.open(raw_path).convert("RGB")
    width, height = SIZE
    canvas = backdrop(width, height)
    draw = ImageDraw.Draw(canvas)
    margin = width * 0.06

    size = round(height * 0.056)
    while True:
        font = caption_font(language, size)
        lines = wrap(draw, title, font, width - margin * 2, language)
        if len(lines) <= 2 or size <= height * 0.043:
            break
        size -= 4
    y = round(height * 0.045)
    line_height = round(size * 1.12)
    for line in lines:
        draw.text((width / 2, y), line, font=font, fill="white", anchor="ma",
                  stroke_width=max(1, round(size * 0.012)), stroke_fill=(16, 72, 136))
        y += line_height

    y += round(height * 0.006)
    small = round(height * 0.0225)
    while draw.textlength(subtitle, font=body_font(language, small)) > width - margin * 2 and small > height * 0.017:
        small -= 2
    draw.text((width / 2, y), subtitle, font=body_font(language, small), fill=(238, 246, 255), anchor="ma")
    y += round(small * 1.5)

    phone(canvas, shot, top=max(y + round(height * 0.018), round(height * 0.205)))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "PNG", optimize=True)


# MARK: - the simulator


def device_udid(name):
    listing = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j").stdout)
    found = []
    for runtime, devices in listing["devices"].items():
        if "iOS" not in runtime:
            continue
        version = runtime.rsplit(".", 1)[-1].replace("iOS-", "").replace("-", ".")
        for device in devices:
            if device["name"] == name:
                found.append((tuple(int(part) for part in version.split(".") if part.isdigit()), device["udid"]))
    if not found:
        sys.exit(f"No available simulator named {name!r}. Add one in Xcode › Windows › Devices and Simulators.")
    return max(found)[1]


def build():
    print("building…", flush=True)
    result = run("xcodebuild", "-project", str(ROOT / "Sunspot.xcodeproj"), "-scheme", "Sunspot",
                 "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(DERIVED),
                 "build", check=False)
    if result.returncode != 0:
        print(result.stdout[-4000:])
        sys.exit("build failed")


def prepare(udid, erase=True):
    if erase:
        run("xcrun", "simctl", "shutdown", udid, check=False)
        run("xcrun", "simctl", "erase", udid)
    run("xcrun", "simctl", "boot", udid, check=False)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    run("xcrun", "simctl", "install", udid, str(APP))
    run("xcrun", "simctl", "privacy", udid, "revoke", "location", BUNDLE, check=False)
    run("xcrun", "simctl", "status_bar", udid, "override", "--time", "13:30", "--batteryState", "charged",
        "--batteryLevel", "100", "--cellularBars", "4", "--wifiBars", "3")


def capture(udid, language, screen, target, expect=SIZE):
    """Launches the app on one screen and waits for it to say it is up."""
    container = pathlib.Path(run("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data").stdout.strip())
    marker = container / "tmp" / "sunplot-shot.json"
    marker.unlink(missing_ok=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    run("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(target))
    before = fingerprint(target)  # whatever is on screen now: the home screen, or the last frame
    for attempt in range(3):
        launch = run("xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE,
                     "-SunspotDemoData", "YES", "-SunspotDemoScreen", screen,
                     "-AppleLanguages", f"({language})", "-AppleLocale", LOCALES[language], check=False)
        if launch.returncode == 0:
            break
        if attempt == 2:
            sys.exit(f"{target.name}: simctl launch failed — {launch.stderr.strip()}")
        time.sleep(2)
    deadline = time.time() + 120
    while not marker.exists():
        if time.time() > deadline:
            sys.exit(f"{target.name}: the app never reported ready")
        time.sleep(0.25)
    hours = json.loads(marker.read_text()).get("hours", "")

    # 🔴 The marker only says the view asked to appear. The first frame arrives much later —
    # a cold launch on a freshly erased simulator took twenty seconds — and screenshotting on
    # a timer caught the home screen or a blank white page. So shoot until the screen stops
    # changing and is no longer what was on it before the launch.
    target.parent.mkdir(parents=True, exist_ok=True)
    previous, settled = None, 0
    deadline = time.time() + 120
    while True:
        run("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(target))
        current = fingerprint(target)
        if current == before:
            settled = 0
        elif current == previous:
            settled += 1
            if settled >= 2:
                break
        else:
            settled = 0
        previous = current
        if time.time() > deadline:
            sys.exit(f"{target.name}: the screen never settled")
        time.sleep(1.0)

    size = Image.open(target).size
    if expect and size != expect:
        sys.exit(f"{target}: captured {size[0]}x{size[1]}, App Store Connect wants {expect[0]}x{expect[1]}")
    return hours


def fingerprint(path):
    """A small grey thumbnail, enough to tell one screen from another."""
    return Image.open(path).convert("L").resize((48, 104), Image.BILINEAR).tobytes()


def review_screenshot():
    """The paywall at 6.5 inches, the size the in-app purchase form accepts."""
    build()
    udid = device_udid(REVIEW_DEVICE)
    prepare(udid, erase=False)
    target = OUT / "review" / "paywall-6.5.png"
    capture(udid, "en", "paywall", target, expect=REVIEW_SIZE)
    Image.open(target).convert("RGB").save(target)  # upload forms want no alpha channel
    print(f"captured {target.relative_to(ROOT)}")


def main():
    if "--review" in sys.argv:
        review_screenshot()
        return
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    languages = only.split(",") if only else list(LOCALES)
    figures = {}
    figures_path = OUT / "raw" / "figures.json"
    if figures_path.exists():
        figures = json.loads(figures_path.read_text())

    if "--frame-only" not in sys.argv:
        build()
        udid = device_udid(DEVICE)
        prepare(udid)
        for language in languages:
            for name, screen in SCREENS:
                target = OUT / "raw" / language / f"{name}.png"
                hours = capture(udid, language, screen, target)
                if name == "01-today" and hours:
                    figures[language] = hours
                print(f"captured {target.relative_to(ROOT)}  {hours}", flush=True)
        figures_path.parent.mkdir(parents=True, exist_ok=True)
        figures_path.write_text(json.dumps(figures, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    done = 0
    for language in languages:
        for name, _ in SCREENS:
            raw = OUT / "raw" / language / f"{name}.png"
            if not raw.exists():
                continue
            title, subtitle = CAPTIONS[name][language]
            title = title.replace("{hours}", figures.get(language, figures.get("en", "")))
            compose(raw, title, subtitle, OUT / "6.1" / language / f"{name}.png", language)
            done += 1
    print(f"{done} framed screenshots in {OUT.relative_to(ROOT)}/6.1/")


if __name__ == "__main__":
    main()
