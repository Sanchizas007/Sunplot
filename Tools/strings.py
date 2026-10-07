#!/usr/bin/env python3
"""Single source of truth for every user-facing string, in fourteen languages.

Translations live one file per language in `Tools/strings/`; `en.json` is the master and
its keys are the text as written in the code (except the SpotKit and InfoPlist keys,
which are symbolic and carry their English text as the value). Writes all three
catalogs — the app's, the SpotKit package's and InfoPlist — from those files.

  python3 Tools/strings.py            regenerate the catalogs
  python3 Tools/strings.py --check    exit 1 if a catalog differs from the files
  python3 Tools/strings.py --coverage <DerivedData>
                                      compare the files with the keys the compiler
                                      extracted from the code in the last build

Never edit the catalogs by hand, and do not let Xcode's own edits reach a commit: Xcode
rewrites them whenever it builds in the IDE.

Every run audits the translations first: same keys everywhere, the same placeholders in
the same order, the same line breaks, nothing left in English by accident and nothing
written in the wrong script. `_origin.json` says which catalog each key belongs to.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLES = ROOT / "Tools" / "strings"
CATALOGS = {
    "app": ROOT / "Sunspot" / "Localizable.xcstrings",
    "kit": ROOT / "Packages" / "SolarCore" / "Sources" / "SpotKit" / "Resources" / "Localizable.xcstrings",
    "info": ROOT / "Sunspot" / "InfoPlist.xcstrings",
}

# The fourteen languages of the app: the universal thirteen plus Turkish.
LANGUAGES = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt-BR", "ru", "tr", "zh-Hans", "zh-Hant"]
TRANSLATED = [language for language in LANGUAGES if language != "en"]

# Positional and plain placeholders both appear here: %@ %lld %d %1$@ %2$d.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|%)")

# The only strings a language may legitimately leave as the English: the brand, botanical
# names and words spelled the same way. Kept exact, language by language, so anything else
# still in English fails the audit instead of slipping into the build.
UNTRANSLATED_OK = {
    "%@ – %@": set(TRANSLATED),
    "%@+": set(TRANSLATED),
    "compass.withBearing": set(TRANSLATED),
    "hours.short": {"de", "nl", "pl", "pt-BR", "es", "it", "fr", "tr"},
    "duration.hours": {"de", "nl"},
    "duration.hoursMinutes": {"de", "nl"},
    "duration.minutes": {"de", "nl", "fr", "it", "es", "pt-BR", "tr", "pl"},
    # Words a language spells exactly as the English does. Checked one by one: anything
    # else still in English is a translation somebody forgot.
    "Aubergine": {"de", "fr"},
    "Clematis": {"de", "es", "it", "nl", "pt-BR", "tr"},
    "Courgettes": {"fr", "nl"},
    "Direction": {"fr"},
    "Fruit": {"nl"},
    "Geraniums": {"nl"},
    "Hostas": {"es", "fr", "it", "pt-BR"},
    "Hydrangea": {"it"},
    "Impatiens": {"es", "fr", "it", "pt-BR"},
    "Name": {"de"},
    "Oregano": {"de", "nl", "pl", "tr"},
    "Roses": {"fr"},
    "compass.w": {"nl"},
}

SCRIPTS = {
    "cyrillic": re.compile(r"[Ѐ-ӿ]"),
    "cjk": re.compile(r"[一-鿿]"),
    "kana": re.compile(r"[぀-ヿ]"),
    "hangul": re.compile(r"[가-힯]"),
}
EXPECTED_SCRIPT = {"ru": "cyrillic", "ja": "kana", "ko": "hangul", "zh-Hans": "cjk", "zh-Hant": "cjk"}
# Simplified forms that must never appear in the traditional Chinese file. Listed one by
# one because the two scripts share most characters and a blanket check is impossible.
SIMPLIFIED_ONLY = "阳时间东开关闭这样树园让种过点击继续购买试书许启长语设备记录档线边现实为专业历观测阴响应该从术经无灯叶结处变够们还个发丰产验认识车门问题数据图风电网页选择钟墙药爱农么岛"


def load(language):
    path = TABLES / f"{language}.json"
    if not path.exists():
        sys.exit(f"missing translation file: {path.relative_to(ROOT)}")
    return json.loads(path.read_text())


def kinds(value):
    """The placeholders in a string, with any numbering stripped off."""
    return [re.sub(r"^%\d+\$", "%", item) for item in PLACEHOLDER.findall(value)]


def keeps_shape(english, text):
    """Whether a translation carries the same placeholders and line breaks.

    A translation may number its placeholders — `%1$@ … %2$lld` — and that is the only way
    to put them in an order the language needs, so a numbered translation is compared
    without regard to order. Unnumbered placeholders must stay in the order the English has
    them: there the position is the only thing binding a placeholder to its value.
    """
    if english.count("\n") != text.count("\n"):
        return False
    if any("$" in item for item in PLACEHOLDER.findall(text)):
        return sorted(kinds(english)) == sorted(kinds(text))
    return kinds(english) == kinds(text)


def numbering_problem(key, language, text):
    """`%1$@ %3$@` with no second is a crash; so is mixing numbered and plain."""
    found = PLACEHOLDER.findall(text)
    numbered = [item for item in found if "$" in item]
    if not numbered:
        return []
    if len(numbered) != len(found):
        return [f"{language}: {key!r} mixes numbered and plain placeholders: {text!r}"]
    indexes = sorted(int(item[1:item.index("$")]) for item in numbered)
    if indexes != list(range(1, len(indexes) + 1)):
        return [f"{language}: {key!r} numbers placeholders {indexes}: {text!r}"]
    return []


def audit(tables, origin):
    problems = []
    master = tables["en"]
    unknown = sorted(set(master) - set(origin))
    if unknown:
        problems.append(f"keys with no catalog in _origin.json: {unknown[:3]}")

    for language in TRANSLATED:
        table = tables[language]
        missing = sorted(set(master) - set(table))
        extra = sorted(set(table) - set(master))
        if missing:
            problems.append(f"{language}: {len(missing)} missing, first: {missing[0]!r}")
        if extra:
            problems.append(f"{language}: unknown keys: {extra[:3]}")

        for key in sorted(set(master) & set(table)):
            english, text = master[key], table[key]
            if not isinstance(text, str) or not text.strip() or text != text.strip("\t "):
                problems.append(f"{language}: {key!r} is empty or padded with spaces")
                continue
            if not keeps_shape(english, text):
                problems.append(f"{language}: {key!r} changes a placeholder or line break: {text!r}")
            problems.extend(numbering_problem(key, language, text))
            if text == english and language not in UNTRANSLATED_OK.get(key, ()):
                problems.append(f"{language}: {key!r} is still English")
            problems.extend(script_problems(language, key, text))
    return problems


def script_problems(language, key, text):
    expected = EXPECTED_SCRIPT.get(language)
    for name, pattern in SCRIPTS.items():
        if not pattern.search(text):
            continue
        if name == expected:
            continue
        # Japanese mixes kana and han; both Chinese scripts are han only.
        if language in ("ja", "zh-Hans", "zh-Hant") and name in ("cjk", "kana"):
            continue
        return [f"{language}: {key!r} is written in {name}: {text!r}"]
    if language == "zh-Hant":
        wrong = {character for character in text if character in SIMPLIFIED_ONLY}
        if wrong:
            return [f"zh-Hant: {key!r} uses simplified {sorted(wrong)}"]
    return []


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(tables, origin, which):
    strings = {}
    for key, english in tables["en"].items():
        if origin[key] != which:
            continue
        localizations = {}
        for language in LANGUAGES:
            value = tables[language][key]
            # A plain English string needs no entry of its own: the key is the value.
            if language == "en" and value == key:
                continue
            localizations[language] = unit(value)
        strings[key] = {"extractionState": "manual", "localizations": localizations}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def render(data):
    # Same shape Xcode writes: two-space indent, " : " separators, sorted keys.
    return json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True) + "\n"


def compiled_keys(derived_data):
    keys = set()
    for path in pathlib.Path(derived_data).rglob("*.stringsdata"):
        data = json.loads(path.read_text())
        for table in data.get("tables", {}).values():
            for entry in table:
                keys.add(entry["key"])
    return keys


def main():
    origin = json.loads((TABLES / "_origin.json").read_text())
    tables = {language: load(language) for language in LANGUAGES}
    problems = audit(tables, origin)
    if problems:
        print(f"{len(problems)} problems in Tools/strings/:")
        print("\n".join(f"  {problem}" for problem in problems[:60]))
        sys.exit(1)

    outputs = {path: render(catalog(tables, origin, which)) for which, path in CATALOGS.items()}

    if "--coverage" in sys.argv:
        derived = sys.argv[sys.argv.index("--coverage") + 1]
        compiled = compiled_keys(derived)
        if not compiled:
            sys.exit(f"no .stringsdata under {derived}: build the app first")
        missing = sorted(compiled - set(tables["en"]))
        print(f"{len(compiled)} keys in the build, {len(tables['en'])} in Tools/strings/en.json")
        if missing:
            print("NOT TRANSLATED (in the code, not in the tables):")
            print("\n".join(f"  {key!r}" for key in missing))
        sys.exit(1 if missing else 0)

    if "--check" in sys.argv:
        stale = [path.name for path, text in outputs.items() if path.read_text() != text]
        if stale:
            sys.exit(f"out of date, run python3 Tools/strings.py: {', '.join(stale)}")
        print(f"catalogs match Tools/strings/ — {len(tables['en'])} keys × {len(LANGUAGES)} languages")
        return

    for path, text in outputs.items():
        path.write_text(text)
        print(f"wrote {path.relative_to(ROOT)}")
    print(f"{len(tables['en'])} keys × {len(LANGUAGES)} languages")


if __name__ == "__main__":
    main()
