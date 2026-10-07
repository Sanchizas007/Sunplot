#!/usr/bin/env python3
"""Builds the pages that must exist before Sunplot can be submitted — in fourteen languages.

    python3 Tools/build-site.py

Output goes to docs/, which is what GitHub Pages serves from this repository:

    docs/index.html                 what the app is           (English)
    docs/privacy/index.html         privacy policy            (App Review will not accept a
    docs/support/index.html         support contact            submission without reachable
    docs/terms/index.html           terms, Apple's licence     privacy and support URLs)
    docs/<language>/…               the same three pages in each of the other thirteen

Texts live one file per language in `Tools/site-strings/`; the addresses are wired into
store/listing.py, which points every store locale at its own language.

Terms are published in English only and linked from every language: they restate Apple's
standard licence, which is itself English, and a translation of a licence is a licence
nobody can rely on.

Generated rather than hand-written so the pages cannot drift apart in wording or appearance,
and so the support address lives in exactly one place.
"""

import json
from pathlib import Path

APP = "Sunplot"
SUPPORT_EMAIL = "zhvnir1345@yahoo.com"
REPO = "https://github.com/Sanchizas007/Sunplot"
# Кто лицензирует приложение. Apple's standard EULA calls this the Application Provider, and
# the store listing, the licence in the repository and these pages must all name the same one.
LICENSOR = "Olexandr Zhovnir"
SITE = "https://sanchizas007.github.io/Sunplot"
UPDATED = "7 October 2026"

ROOT = Path(__file__).resolve().parent.parent
STRINGS = ROOT / "Tools" / "site-strings"
# English sits at the root; every other language gets a folder named after it, and those
# folder names are what store/listing.py points each store locale at.
LANGUAGES = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt-BR", "ru", "tr", "zh-Hans", "zh-Hant"]
ENDONYM = {
    "en": "English", "de": "Deutsch", "es": "Español", "fr": "Français", "it": "Italiano",
    "ja": "日本語", "ko": "한국어", "nl": "Nederlands", "pl": "Polski", "pt-BR": "Português",
    "ru": "Русский", "tr": "Türkçe", "zh-Hans": "简体中文", "zh-Hant": "繁體中文",
}
PREFIX = {language: ("" if language == "en" else f"{language}/") for language in LANGUAGES}
TEXT = {language: json.loads((STRINGS / f"{language}.json").read_text(encoding="utf-8"))
        for language in LANGUAGES}
PAGES = ["", "privacy", "support"]  # terms is English-only, see the note above

# Sampled from the app's own icon.
STYLE = """
:root {
  --ink: #241a12; --muted: #6b5a4c; --rule: #e8ddd2;
  --page: #fffaf4; --card: #ffffff; --accent: #f36511;
}
@media (prefers-color-scheme: dark) {
  :root {
    --ink: #f6ece2; --muted: #b3a294; --rule: #33291f;
    --page: #16110c; --card: #1f1811; --accent: #fda43a;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--page); color: var(--ink);
  font: 17px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  -webkit-text-size-adjust: 100%;
}
.wrap { max-width: 44rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
nav { display: flex; flex-wrap: wrap; gap: 1.1rem; font-size: .95rem; margin-bottom: 2.5rem; }
nav a { color: var(--muted); text-decoration: none; }
nav a[aria-current] { color: var(--ink); font-weight: 600; }
h1 { font-size: 2rem; line-height: 1.2; margin: 0 0 1rem; letter-spacing: -0.01em; }
h2 { font-size: 1.2rem; margin: 2rem 0 .5rem; }
h3 { font-size: 1rem; margin: 1.4rem 0 .3rem; }
p { margin: 0 0 1rem; }
.lede { font-size: 1.15rem; color: var(--muted); }
a { color: var(--accent); }
.card {
  background: var(--card); border: 1px solid var(--rule); border-radius: 14px;
  padding: 1rem 1.2rem; margin: 1.5rem 0;
}
.card p:last-child { margin-bottom: 0; }
.langs { margin: 2.5rem 0 0; font-size: .85rem; color: var(--muted); display: flex; flex-wrap: wrap; gap: .6rem; }
.langs a { color: var(--muted); text-decoration: none; }
.langs strong { color: var(--ink); font-weight: 600; }
footer { margin-top: 3rem; padding-top: 1.2rem; border-top: 1px solid var(--rule);
  color: var(--muted); font-size: .9rem; }
ul { padding-left: 1.2rem; }
li { margin-bottom: .45rem; }
"""


def url(language, slug):
    return f"{SITE}/{PREFIX[language]}{slug + '/' if slug else ''}"


def page(language, slug, title, description, body):
    text = TEXT[language]
    here = f"{PREFIX[language]}{slug + '/' if slug else ''}index.html"

    def link(target, label, english=False):
        href = f"{SITE}/" + ("" if english else PREFIX[language]) + (f"{target}/" if target else "")
        current = ' aria-current="page"' if target == slug else ""
        return f'<a href="{href}"{current}>{label}</a>'

    switcher = " ".join(
        f"<strong>{ENDONYM[other]}</strong>" if other == language
        else f'<a href="{url(other, slug)}" hreflang="{other}">{ENDONYM[other]}</a>'
        for other in LANGUAGES
    )
    alternates = "\n".join(
        f'<link rel="alternate" hreflang="{other}" href="{url(other, slug)}">' for other in LANGUAGES
    ) + f'\n<link rel="alternate" hreflang="x-default" href="{url("en", slug)}">'

    html = f"""<!doctype html>
<html lang="{language}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — {APP}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{url(language, slug)}">
{alternates}
<style>{STYLE}</style>
</head>
<body>
<div class="wrap">
<nav>
  {link("", text["nav"]["home"])}
  {link("privacy", text["nav"]["privacy"])}
  {link("support", text["nav"]["support"])}
  {link("terms", text["nav"]["terms"], english=True)}
  <a href="{REPO}">Source</a>
</nav>
{body}
<p class="langs">{switcher}</p>
<footer>
  <p>{APP} · {text["updated"]} {UPDATED} · <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a></p>
  <p>© 2026 {LICENSOR}. All rights reserved.</p>
</footer>
</div>
</body>
</html>
"""
    out = ROOT / "docs" / here
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    return here


TERMS = f"""
<h1>Terms</h1>
<p class="lede">Sunplot is licensed, not sold, under Apple's standard licence for applications.</p>

<h2>Who licenses it</h2>
<p>Sunplot is published and licensed by <strong>{LICENSOR}</strong>, who holds the copyright
in the application, its name and its source code. Apple distributes it and is not a party to
this licence. Any question about permissions, reuse or licensing goes to the address at the
foot of this page.</p>

<h2>The licence</h2>
<p>Use of Sunplot is governed by Apple's Licensed Application End User License Agreement,
which you can read at
<a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">apple.com/legal/internet-services/itunes/dev/stdeula</a>.</p>

<h2>The purchase</h2>
<p>Sunplot is free to download. One optional purchase unlocks the year view, saving more than
one spot, and the widget. It is a single payment: there is no subscription, nothing renews and
there is nothing to cancel. Refunds are handled by Apple, through the same account the
purchase was made from.</p>

<h2>What the numbers are</h2>
<p>Sunplot computes the sun's position from published astronomical algorithms and subtracts
the skyline you trace. It is accurate to the care taken tracing and to the phone's own compass,
both of which the app reports on. It is a gardening and planning tool, not a survey
instrument: do not use it where a wrong answer would be dangerous or expensive, and check
anything that matters against a professional measurement.</p>

<h2>Source</h2>
<p>The source is published at <a href="{REPO}">{REPO}</a> to be read, not reused. The
repository is public for two reasons: these pages are served from it, and the work can be
inspected. It is not open source.</p>
<p>Copyright in Sunplot — its source code, its name, its icon and the wording of its screens —
is held solely by {LICENSOR}, and all rights are reserved. Publication grants no licence, by
implication or otherwise, to copy any part of it into another project by any means, to use it
in any product or service, to modify or distribute it, to publish a derived or substantially
similar application to any store, or to train machine-learning models on it. The licence in
that repository sets out the whole of what is and is not permitted.</p>

<h2>Contact</h2>
<p><a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a></p>
"""

written = []
for language in LANGUAGES:
    text = TEXT[language]
    for slug in PAGES:
        section = text["home"] if slug == "" else text[slug]
        lede = section["lede"].replace("{EMAIL}", f'<a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>')
        body = f'<h1>{section["title"]}</h1>\n<p class="lede">{lede}</p>\n{section["body"]}'
        description = section["lede"].replace("{EMAIL}", SUPPORT_EMAIL)
        written.append(page(language, slug, section["title"], description, body))
written.append(page("en", "terms", "Terms", "Terms of use for Sunplot.", TERMS))

(ROOT / "docs" / "robots.txt").write_text(
    f"User-agent: *\nAllow: /\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8"
)

locations = [url(language, slug) for language in LANGUAGES for slug in PAGES] + [f"{SITE}/terms/"]
urls = "".join(f"  <url><loc>{location}</loc></url>\n" for location in locations)
(ROOT / "docs" / "sitemap.xml").write_text(
    f'<?xml version="1.0" encoding="UTF-8"?>\n'
    f'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}</urlset>\n',
    encoding="utf-8",
)

# GitHub Pages otherwise runs the output through Jekyll, which ignores folders it does not
# recognise and quietly drops files beginning with an underscore.
(ROOT / "docs" / ".nojekyll").write_text("", encoding="utf-8")

print(f"{len(written)} pages in docs/ — {len(LANGUAGES)} languages")
print("docs/robots.txt\ndocs/sitemap.xml\ndocs/.nojekyll")
