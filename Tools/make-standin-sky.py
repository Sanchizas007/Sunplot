#!/usr/bin/env python3
"""Makes the picture the Sky screen shows in screenshot runs, where a simulator has no camera.

    python3 -X utf8 Tools/make-standin-sky.py [--write-demo]

Reads  screenshots/source/standin-photo.jpg   (credit in Tools/standin-photo-credit.txt)
Writes screenshots/standin-sky.jpg            1206×2622, the photo cut to the shape of the screen
       Tools/screenshots/sky-photo-ridge.json  the skyline in the photo, as the app measures one

The skyline is the point. The cyan line the app draws is the garden's traced horizon, so the
demo garden's horizon has to be the one in the photograph — otherwise the line floats over a
picture it does not agree with. The photo's roofline and tree tops are found here, turned into
directions (azimuth, elevation) with the same projection the app uses, and pasted into
Sunspot/App/Demo.swift between its `photo ridge` markers by `--write-demo`. Every number in
the screenshots (hours, months, the comparison) is then worked out from that horizon.

The projection is SolarCore.SkyProjection written out again in Python. The Sky overlay maps
the sky onto the safe area, which on an iPhone 17 Pro is 402×730 points inside the 402×874
screen, drawn from the top of the screen; fitting this against a capture of the old demo
skyline agrees to 0.6 px out of 2622, which is why those two numbers are here.
"""
import json
import math
import pathlib
import re
import sys

import numpy as np
from PIL import Image, ImageFilter
from numpy.lib.stride_tricks import sliding_window_view

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHOTO = ROOT / "screenshots" / "source" / "standin-photo.jpg"
OUT = ROOT / "screenshots" / "standin-sky.jpg"
RIDGE_JSON = ROOT / "Tools" / "screenshots" / "sky-photo-ridge.json"
DEMO = ROOT / "Sunspot" / "App" / "Demo.swift"

W, H = 1206, 2622                  # pixels of the screenshot (3×)
VIEW_W, VIEW_H = 402.0, 730.0      # points the Sky overlay maps the sky onto
BEARING, PITCH = 190.0, 28.0       # Demo.skyBearing, Demo.skyPitch
CAMERA_FOV = 68.0                  # what CameraFeed reports in a simulator

# Which slice of the 6000×4000 photo becomes the screen: its full height, 1840 px across,
# starting here — the shed's right half with the sun on its roof, and the tree beyond it.
CROP_X = 2520


# ── the photo, cut and graded ───────────────────────────────────────────────────────────────
def picture():
    photo = Image.open(PHOTO).convert("RGB")
    width = round(photo.height * W / H)
    crop = photo.crop((CROP_X, 0, CROP_X + width, photo.height)).resize((W, H), Image.LANCZOS)
    a = np.asarray(crop).astype(np.float32) / 255
    # Richer colour: the photo is a little flat for a screen that is the whole point of the app.
    grey = a.mean(axis=2, keepdims=True)
    a = np.clip(grey + (a - grey) * 1.28, 0, 1)
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    x = np.linspace(0, 1, W, dtype=np.float32)[None, :, None]
    # A deeper blue overhead, fading out by the horizon: the sky in the photo is pale, and the
    # clock, the yellow arc and the sun need something to stand against.
    k = np.clip(1 - y / 0.52, 0, 1) ** 1.2
    a = a * (1 - k + k * np.array([0.38, 0.52, 1.0], np.float32))
    # And more of the sunset the photo was taken in: a warm band hugging the horizon, strongest
    # round the sun, which sits low on the left.
    glow = np.exp(-(((y - 0.50) / 0.13) ** 2)) * (0.55 + 0.45 * np.exp(-(((x - 0.20) / 0.55) ** 2)))
    warm = np.array([1.0, 0.52, 0.22], np.float32)
    a = 1 - (1 - a) * (1 - warm * glow * 0.30)
    return a


# ── the skyline in it ───────────────────────────────────────────────────────────────────────
def find_ridge(a):
    """Top edge of the roof and trees, in pixels, one value per column."""
    gray = np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("L")
                      .filter(ImageFilter.GaussianBlur(3))).astype(np.float32)
    drop = gray[6:] - gray[:-6]                       # darker as you go down: sky into object
    ys = np.argmin(drop[1000:1560], axis=0).astype(np.float32) + 1003
    padded = np.pad(ys, 25, mode="edge")
    ys = np.median(sliding_window_view(padded, 51), axis=1)
    # Two places the edge finder is wrong, fixed by eye: a dark cloud sitting just above the
    # roof in the glare of the sun (the roof is a flat line there), and the crown of the big
    # tree running off the right-hand edge.
    left, right = ys[90], ys[310]
    ys[90:311] = np.linspace(left, right, 221)
    ys[1165:] = 1340
    return ys


class Projection:
    """SolarCore.SkyProjection, screen → sky."""

    def __init__(self):
        a, e = math.radians(BEARING), math.radians(PITCH)
        forward = (math.cos(e) * math.cos(a), -math.cos(e) * math.sin(a), math.sin(e))
        out = tuple(-v for v in forward)
        right = (-math.sin(a), -math.cos(a), 0.0)
        top = (out[1] * right[2] - out[2] * right[1], out[2] * right[0] - out[0] * right[2],
               out[0] * right[1] - out[1] * right[0])
        self.rotation = np.array([right, top, out])
        half_wide = math.tan(math.radians(CAMERA_FOV / 2))
        half_narrow = half_wide / (4 / 3)
        aspect = VIEW_W / VIEW_H
        if aspect > half_narrow / half_wide:
            half_h, half_v = half_narrow, half_narrow / aspect
        else:
            half_v, half_h = half_wide, half_wide * aspect
        self.tan_h, self.tan_v = half_h, half_v

    def direction(self, u, v):
        x = (u / 3) / VIEW_W * 2 - 1
        y = (v / 3) / VIEW_H * 2 - 1
        ray = np.array([x * self.tan_h, -y * self.tan_v, -1.0])
        world = self.rotation.T @ ray
        world /= np.linalg.norm(world)
        return math.degrees(math.atan2(-world[1], world[0])) % 360, math.degrees(math.asin(world[2]))


def ridge_samples(ridge):
    """(azimuth, elevation) every 1.5°, taking the highest point of the trees and roof in each."""
    projection = Projection()
    points = [projection.direction(u + 0.5, ridge[u]) for u in range(W)]
    azimuths = np.array([p[0] for p in points])
    elevations = np.array([p[1] for p in points])
    samples = []
    first = math.ceil((azimuths.min() + 0.75) / 1.5)
    last = math.floor((azimuths.max() - 0.75) / 1.5)
    for k in range(first, last + 1):
        centre = k * 1.5
        inside = np.nonzero(np.abs(azimuths - centre) <= 0.75)[0]
        best = inside[np.argmax(elevations[inside])]
        samples.append((centre, round(float(elevations[best]), 2)))
    return samples


def demo_block(samples):
    rows = ",\n".join("        (" + f"{az:g}, {el:.2f}" + ")" for az, el in samples)
    return ("    // BEGIN photo ridge — written by Tools/make-standin-sky.py, do not edit by hand\n"
            "    private static let photoRidge: [(azimuth: Double, elevation: Double)] = [\n"
            + rows + "\n    ]\n    // END photo ridge\n")


def write_demo(samples):
    text = DEMO.read_text()
    pattern = re.compile(r"    // BEGIN photo ridge.*?    // END photo ridge\n", re.S)
    if not pattern.search(text):
        sys.exit("Demo.swift has no `photo ridge` block yet: add the markers first")
    DEMO.write_text(pattern.sub(lambda _: demo_block(samples), text))
    print(f"wrote {len(samples)} samples into {DEMO.relative_to(ROOT)}")


if __name__ == "__main__":
    image = picture()
    Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8)).save(OUT, quality=95)
    print(f"wrote {OUT.relative_to(ROOT)}  {W}×{H}")
    samples = ridge_samples(find_ridge(image))
    RIDGE_JSON.write_text(json.dumps(samples))
    print(f"skyline: {len(samples)} samples from azimuth {samples[0][0]:g}° to {samples[-1][0]:g}°, "
          f"elevation {min(s[1] for s in samples):.1f}°…{max(s[1] for s in samples):.1f}°")
    if "--write-demo" in sys.argv:
        write_demo(samples)
