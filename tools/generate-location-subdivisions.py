#!/usr/bin/env python3
"""Generate localized ISO 3166-2 labels used by the location selector.

The checked-in city database keeps GeoNames IDs for profile compatibility.  Its
``subcountry_code`` field is the stable identity; display names come from the
Unicode CLDR release pinned below.
"""

import json
from pathlib import Path
from urllib.request import urlopen
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parent.parent
CLDR_RELEASE = "release-48-2"
CLDR_URL = (
    "https://raw.githubusercontent.com/unicode-org/cldr/"
    f"{CLDR_RELEASE}/common/subdivisions/{{language}}.xml"
)


def subdivision_codes():
    locations = json.loads((ROOT / "resources" / "locations.json").read_text(encoding="utf-8"))
    return sorted({location["subcountry_code"] for location in locations if location.get("subcountry_code")})


def cldr_names(language, codes):
    with urlopen(CLDR_URL.format(language=language)) as response:
        document = ElementTree.fromstring(response.read())
    wanted = {code.lower().replace("-", ""): code for code in codes}
    names = {}
    for subdivision in document.findall("./localeDisplayNames/subdivisions/subdivision"):
        code = wanted.get(subdivision.attrib.get("type"))
        if code and subdivision.text:
            names[code] = subdivision.text
    return dict(sorted(names.items()))


def main():
    codes = subdivision_codes()
    result = {
        "_meta": {
            "source": "Unicode CLDR",
            "source_url": "https://github.com/unicode-org/cldr/tree/release-48-2/common/subdivisions",
            "release": CLDR_RELEASE,
            "license": "Unicode-3.0",
        }
    }
    for locale in sorted(path.name for path in (ROOT / "locale").iterdir() if path.is_dir()):
        names = cldr_names(locale.split("-", 1)[0], codes)
        if names:
            result[locale] = names
    output = ROOT / "resources" / "location_subdivisions.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
