# Sunplot

**How much sun does this spot actually get?**

Every seed packet, plant label and solar-panel spec is written in hours of direct sun.
Almost nobody knows what their own garden, balcony or roof actually gets — so the tomatoes
go in the shady corner and never ripen, and the panels go on the side of the roof the
neighbour's lime tree shades from October.

Sunplot answers the question with a number.

Other sun apps show you where the sun is. That is the easy half. The half that decides the
answer is what stands in the way: the fence, the garage, the tree next door. Sunplot lets
you trace that skyline with the camera, then walks the day a minute at a time and counts
only the light that actually reaches the spot.

> **This is published to be read, not reused.** Copyright in Sunplot — its source, its name,
> its icon and the wording of its screens — belongs solely to Olexandr Zhovnir, and all rights
> are reserved. The repository is public because the App Store requires a privacy policy,
> support page and terms, and those are served from it; being able to read something is not
> permission to use it. Copying any part of this into another project, by hand or by machine,
> or publishing anything derived from it, needs written permission first. See [`LICENSE`](LICENSE).

---

## Status

Built, translated, and shot for the store. 187 tests pass; the purchase has been made on a
real phone and the skyline has been traced on one. iPhone only, iOS 17 and up, one payment
that never expires.

| Piece | State |
| --- | --- |
| `SolarCore` — sun position, skyline, sun-hours, sky projection | ✅ 84 tests |
| Today — the answer in hours, graded the way plant labels are | ✅ |
| Map — where the sun arrives from, leaves towards, and is now | ✅ |
| Sky — the arc over the live camera, skyline traced by finger | ✅ tried on an iPhone 14 |
| Year — the season said in a sentence, then drawn | ✅ |
| Several spots, and which of them is better | ✅ |
| What will grow at this spot | ✅ |
| Saving spots and their skylines | ✅ |
| Home-screen widget | ✅ |
| A word before the sun arrives | ✅ |
| Paywall — one purchase, StoreKit 2 decides who has paid; RevenueCat only watches | ✅ bought on a real phone |
| English, German, French | ✅ 199 strings, checked against the keys the app really asks for |
| App Store screenshots | ✅ generated; the Sky frame wants a real garden behind it |
| Privacy manifest, app and widget | ✅ purchase history and advertising data (RevenueCat), neither linked nor tracking |
| Export compliance, device family, version | ✅ no non-exempt encryption, iPhone, 1.0 |

On a first real tracing session the app captured 860 directions covering 217° of horizon —
94% of the 251° the sun crosses at that latitude — with no compass jitter: the line deviated
0.57° on average from its own local mean. That spot gets nine hours of sun in late August and
none at all in December, which is exactly the sort of answer the app exists to give.

## The engine

`Packages/SolarCore` is a standalone Swift package with no dependencies. It runs anywhere
Swift runs, which means the maths can be tested from the command line without a simulator.

```bash
cd Packages/SolarCore
swift test
```

What it does:

- **`Solar.position(at:coordinate:)`** — the sun's azimuth and elevation for any place and
  moment, using the standard low-precision equations from Meeus's *Astronomical Algorithms*.
- **`HorizonProfile`** — the skyline around a spot, as a ring of measured heights that
  interpolates between samples and wraps across north.
- **`Solar.sunDay(containing:coordinate:timeZone:horizon:)`** — stretches of direct sun,
  the total, the first and last sun, and the longest unbroken run.
- **`Solar.sunYear(year:coordinate:timeZone:horizon:)`** — the same figure for every day of
  the year, for showing a bed that bakes in July sitting in shadow from October.
- **`SunExposure`** — grades a spot the way plant labels are worded: full sun, part sun,
  part shade, full shade.

### On accuracy

The engine is checked two ways, because self-consistency is not correctness.

**Against physics.** Quantities fixed by the geometry of the solar system, not by any
implementation of it: declination peaking at the axial tilt on the solstices and crossing
zero at the equinoxes, noon elevation equal to 90° minus the angle between your latitude and
the sun's, the noon sun due south in the northern hemisphere and due north in the southern,
midnight sun above the Arctic Circle and polar night below the Antarctic, the equation of
time staying inside its known envelope.

**Against the world.** Sunrise and sunset were compared with two independent providers on
2026-08-24. Where those two disagreed with each other, this engine matched Open-Meteo to
within a fraction of a minute; a separate check showed the other provider places sunrise
with the sun's centre near −1.08°, rather than the −0.833° its own documentation specifies.
Those reference times are pinned in `SunriseReferenceTests` so the agreement cannot quietly
rot.

Sunrise is taken at the moment the sun's apparent upper limb clears the skyline — 34
arcminutes of atmospheric refraction plus the disc's own 16-arcminute radius. Comparing the
bare geometric centre against a flat horizon instead costs a spot five to twelve minutes at
each end of the day, depending on latitude. Transitions are refined by bisection rather than
left on a one-minute grid, because a grid error always falls the same way and shortens the
day.

## Layout

```
Packages/SolarCore/        the maths, dependency-free and testable from a terminal
  Sources/SolarCore/
    Geometry.swift             coordinates, angles
    SolarPositionCalculator.swift  where the sun is
    HorizonProfile.swift       what stands in the way
    SunHours.swift             what that adds up to
  Tests/SolarCoreTests/
```

## Tools

```
Tools/check.sh              engine, build, purchase configuration, translations, app tests
Tools/release.sh            check, archive, export a signed .ipa, validate, upload
Tools/screenshots.sh        the App Store set — six screens, no taps
Tools/check-localisation.py the keys SwiftUI would look up, checked against the catalogue
Tools/make-project.py       regenerates Sunspot.xcodeproj  ← внутреннее имя, см. ниже
Tools/build-site.py         the pages served from docs/
```

`check.sh` is the one to run after a change; the rest it calls or you call by hand.

The app is **Sunplot**, and so is everything it registers with Apple: `app.sunplot`,
`group.app.sunplot`, `app.sunplot.full`. The plan had been to leave those alone on the grounds
that nobody sees them — until the first archive build failed with *the app identifier
"app.sunspot" cannot be registered to your development team because it is not available*.
Another developer holds it. It had never been ours: the build that ran on a phone in August was
signed with a wildcard profile, which needs no identifier of its own and cannot carry an App
Group either, so nothing had ever asked Apple for the real one.

The target, the folders and the Xcode project are still named Sunspot. Those are ours to
rename whenever it is convenient and nobody outside ever reads them.

`make-project.py` writes the scheme byte for byte as Xcode writes it, so opening Edit Scheme
no longer produces a diff and regenerating no longer undoes what Xcode just saved. The
StoreKit configuration path in it has always been correct; what used to change underneath it
was the formatting of the file around it.

There is no analytics, no account and no server of our own. Nothing the app works out — the
location, the spots, the traced skylines — leaves the phone. The one third-party SDK is
RevenueCat (`purchases-ios`), in observer mode: StoreKit 2 still decides who has paid, and
`PurchaseTracker` only tells RevenueCat about a purchase and, once per install, hands it Apple's
AdServices token so an Apple Ads campaign can be credited. That is exactly what the privacy
manifest, the App Privacy answers and the privacy policy on the site declare: purchase history
and advertising data, neither linked to the person nor used for tracking. The public SDK key is
`REVENUECAT_PUBLIC_KEY` in `Tools/make-project.py`; empty, the build reports nothing.

The screenshot set is seeded from a launch argument rather than by tapping through the app,
so it can be thrown away and shot again from scratch whenever a screen moves. The same
garden, the same traced skyline, the same half past one in the afternoon, every time.
English by default; `Tools/screenshots.sh de fr` shoots the other two, in gardens of their
own. One frame is worth retaking by hand: the Sky screen has a real camera behind it on a
phone and a plain gradient in a simulator, and the gradient sells nothing.

The frames themselves are not committed; `screenshots/README.md`, beside them, says which
frame goes in which slot in App Store Connect and what Apple checks.

---

## Copyright and rights

Copyright © 2026 Olexandr Zhovnir. All rights reserved. Sunplot, its source code, its name,
its icon and the wording of its screens belong solely to him. None of it is in the public
domain and no open-source licence applies to any of it.

**Public to read, not open source.** The repository is public for two practical reasons: the
privacy policy, support page and terms that the App Store requires are served from it through
GitHub Pages, and the work is published so it can be inspected, linked to and discussed. That
is the whole of it. A public repository is not an offer of a licence, and a fork the platform
makes for you is not one either.

No licence is granted — by publication, by implication or by silence — to copy any part of
this into another project by any means, including rewriting it in another language or having
a machine do it; to use it in any product or service, commercial or not; to modify, merge,
publish, distribute, sublicense or sell it; to ship a derived or substantially similar
application to any store; to use the name, icon or screenshots for another application; or to
train machine-learning models on it.

Reading the code, learning from it and quoting short excerpts with attribution is welcome.
Shipping it, in whole or in part, is not.

For anything else, ask first, and wait for a written answer. See [`LICENSE`](LICENSE) for the
full terms.
