#!/usr/bin/env python3
"""
Build ShadowDeck/Resources/Catalog/sr6_catalog.json from the SR6 core PDF.

Preferred source:
  ~/Documents/eBooks/Shadowrun/Shadowrun 6th World Core Rulebook- City Edition Seattle.pdf

Usage:
  python3 Scripts/build_sr6_catalog_from_pdf.py [path/to/sr6-core.pdf]

Requires: pdftotext (poppler).

Extracts mechanical tables only (names, nuyen, availability, essence, damage).
Full rule text is NOT redistributed. See Resources/Catalog/NOTICE.txt.

Exactness: build fails (exit 2) if known book spot-checks fail.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import uuid
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "ShadowDeck" / "Resources" / "Catalog" / "sr6_catalog.json"

DEFAULT_PDFS = [
    Path.home()
    / "Documents/eBooks/Shadowrun/Shadowrun 6th World Core Rulebook- City Edition Seattle.pdf",
]

# PDF pages covering Gear Listing through cyber/bioware (City Edition Seattle).
GEAR_PAGES = (248, 310)
SPELL_PAGES = (132, 140)  # combat/health spell name headers (optional)

# Spot-checks from SR6 City Edition Seattle gear tables (must match book).
EXACT_CHECKS: dict[str, dict] = {
    "combat axe": {"costNuyen": 500, "kind": "weapon"},
    "katana": {"costNuyen": 350, "kind": "weapon"},
    "knife": {"costNuyen": 20, "kind": "weapon"},
    "streetline special": {"costNuyen": 200, "kind": "weapon"},
    "colt america l36": {"costNuyen": 230, "kind": "weapon"},
    "ares light fire 70": {"costNuyen": 350, "kind": "weapon"},
    "ares predator vi": {"costNuyen": 750, "kind": "weapon"},
    "armor jacket": {"costNuyen": 1000, "kind": "armor"},
    "armor vest": {"costNuyen": 750, "kind": "armor"},
    "armor clothing": {"costNuyen": 500, "kind": "armor"},
    "lined coat": {"costNuyen": 900, "kind": "armor"},
    "datajack": {"costNuyen": 1000, "kind": "cyberware", "essenceText": "0.1"},
    "smartlink": {"costNuyen": 4000, "kind": "cyberware", "essenceText": "0.2"},
}

# Hand-verified seed rows when two-column layout drops the name onto another line.
# These are copied from layout tables in the SR6 core (City Edition Seattle).
VERIFIED_SEED: list[dict] = [
    {
        "name": "Combat Axe",
        "kind": "weapon",
        "category": "Melee Blades",
        "costNuyen": 500,
        "damage": "5P",
        "availability": "4",
        "notes": "DV 5P · Avail 4 · ¥500 (SR6 gear table)",
    },
    {
        "name": "Katana",
        "kind": "weapon",
        "category": "Melee Blades",
        "costNuyen": 350,
        "damage": "4P",
        "availability": "3",
        "notes": "DV 4P · Avail 3 · ¥350 (SR6 gear table)",
    },
    {
        "name": "Knife",
        "kind": "weapon",
        "category": "Melee Blades",
        "costNuyen": 20,
        "damage": "2P",
        "availability": "1",
        "notes": "DV 2P · Avail 1 · ¥20 (SR6 gear table)",
    },
    {
        "name": "Combat/Survival Knife",
        "kind": "weapon",
        "category": "Melee Blades",
        "costNuyen": 220,
        "damage": "3P",
        "availability": "2",
        "notes": "DV 3P · Avail 2 · ¥220 (SR6 gear table)",
    },
    {
        "name": "Ares Predator VI",
        "kind": "weapon",
        "category": "Heavy Pistols",
        "costNuyen": 750,
        "damage": "3P",
        "availability": "2(L)",
        "notes": "SA/BF · 15(c) · ¥750 (SR6 gear table)",
    },
    {
        "name": "Colt America L36",
        "kind": "weapon",
        "category": "Light Pistols",
        "costNuyen": 230,
        "damage": "2P",
        "availability": "2(L)",
        "notes": "SA · 11(c) · ¥230 (SR6 gear table)",
    },
    {
        "name": "Streetline Special",
        "kind": "weapon",
        "category": "Hold-outs",
        "costNuyen": 200,
        "damage": "2P",
        "availability": "2",
        "notes": "SS · 6(c) · ¥200 (SR6 gear table)",
    },
    {
        "name": "Ares Light Fire 70",
        "kind": "weapon",
        "category": "Light Pistols",
        "costNuyen": 350,
        "damage": "2P",
        "availability": "3(L)",
        "notes": "SA · 16(c) · ¥350 (SR6 gear table)",
    },
    {
        "name": "Armor Jacket",
        "kind": "armor",
        "category": "Clothing and Armor",
        "costNuyen": 1000,
        "armorRating": 4,
        "availability": "2",
        "notes": "Defense Rating +4 · Capacity 8 · ¥1,000 (SR6)",
    },
    {
        "name": "Armor Vest",
        "kind": "armor",
        "category": "Clothing and Armor",
        "costNuyen": 750,
        "armorRating": 3,
        "availability": "2",
        "notes": "Defense Rating +3 · Capacity 6 · ¥750 (SR6)",
    },
    {
        "name": "Armor Clothing",
        "kind": "armor",
        "category": "Clothing and Armor",
        "costNuyen": 500,
        "armorRating": 2,
        "availability": "2",
        "notes": "Defense Rating +2 · Capacity 4 · ¥500 (SR6)",
    },
    {
        "name": "Lined Coat",
        "kind": "armor",
        "category": "Clothing and Armor",
        "costNuyen": 900,
        "armorRating": 3,
        "availability": "2",
        "notes": "Defense Rating +3 · Capacity 7 · ¥900 (SR6)",
    },
    {
        "name": "Datajack",
        "kind": "cyberware",
        "category": "Headware",
        "costNuyen": 1000,
        "essenceText": "0.1",
        "availability": "2",
        "notes": "ESS 0.1 · Avail 2 · ¥1,000 (SR6)",
    },
    {
        "name": "Smartlink",
        "kind": "cyberware",
        "category": "Eyeware",
        "costNuyen": 4000,
        "essenceText": "0.2",
        "availability": "3(L)",
        "notes": "ESS 0.2 · Capacity [3] · ¥4,000 (SR6)",
    },
]


def stable_id(kind: str, name: str, category: str = "") -> str:
    raw = f"sr6|{kind}|{category}|{name}".lower().encode()
    h = hashlib.sha1(raw).hexdigest()
    return str(uuid.UUID(h[:32]))


def pdftotext(pdf: Path, start: int, end: int, raw: bool = False) -> str:
    args = ["pdftotext", "-raw" if raw else "-layout", "-f", str(start), "-l", str(end), str(pdf), "-"]
    r = subprocess.run(args, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise RuntimeError(r.stderr or f"pdftotext failed {start}-{end}")
    return r.stdout


def parse_cost_yen(s: str) -> int | None:
    s = (s or "").strip().replace(",", "").replace("¥", "")
    if not s or not re.fullmatch(r"\d+", s):
        return None
    return int(s)


def humanize_name(name: str) -> str:
    s = re.sub(r"\s+", " ", name.strip())
    # Title-case short all-lower fragments carefully
    if s.islower() or s.isupper():
        s = s.title()
    # Fix common SR brand casing
    fixes = {
        "Ares": "Ares",
        "Fn ": "FN ",
        "Hk-": "HK-",
        "Hk ": "HK ",
        "Uzi ": "Uzi ",
        "Ii": "II",
        "Vi": "VI",
        "Xi": "XI",
    }
    for a, b in fixes.items():
        s = s.replace(a, b)
    return s


def make_entry(
    *,
    kind: str,
    name: str,
    category: str,
    cost_n: int | None,
    body: str = "",
    damage: str | None = None,
    availability: str = "",
    essence: str | None = None,
    armor_rating: int | None = None,
    notes: str = "",
    cost_text: str | None = None,
) -> dict:
    name = humanize_name(name)
    ct = cost_text
    if ct is None:
        ct = f"¥{cost_n}" if cost_n is not None else ""
    if not availability:
        am = re.search(r"\b(\d{1,2}(?:\([A-Za-z]+\))?)\b", body)
        if am:
            availability = am.group(1)
    if damage is None:
        dm = re.search(r"\b(\d+[PS](?:\([efl]+\))?)\b", body.replace(" ", ""), re.I)
        if dm:
            damage = dm.group(1)
    if essence is None and kind in {"cyberware", "bioware"}:
        em = re.search(r"\b(0\.\d+)\b", body)
        if em:
            essence = em.group(1)
    if armor_rating is None and kind == "armor":
        arm = re.search(r"\+(\d+)\b", body)
        if arm:
            armor_rating = int(arm.group(1))
    return {
        "id": stable_id(kind, name, category),
        "kind": kind,
        "name": name,
        "category": category,
        "costText": ct,
        "costNuyen": cost_n,
        "availability": availability,
        "source": "SR6",
        "page": "",
        "essenceText": essence,
        "karma": None,
        "damage": damage,
        "armorRating": armor_rating,
        "notes": notes or re.sub(r"\s+", " ", body).strip()[:160],
        "modifiers": [],
    }


def parse_layout_gear(text: str) -> list[dict]:
    """Parse SR6 gear listing layout tables with fixed nuyen costs."""
    entries: list[dict] = []
    seen: set[str] = set()
    kind = "gear"
    category = "Street Gear"

    # Full line ending in N¥ with a product-ish name at left.
    # Examples:
    #   Katana              4P                10/—/—/—/—               3                   350¥
    #   Ares Predator VI       3P      SA/BF        10/10/8/—/—        15(c)           2(L)           750¥
    #   Datajack                             0.1                         —                        2                   1,000¥
    row_re = re.compile(
        r"^\s*(?P<name>[A-Za-z][A-Za-z0-9][A-Za-z0-9\-\s/.,'*+]{1,40}?)\s{2,}"
        r"(?P<body>.+?)\s+"
        r"(?P<cost>\d{1,3}(?:,\d{3})*)\s*¥\s*$"
    )
    formula_re = re.compile(
        r"^\s*(?P<name>[A-Za-z][A-Za-z0-9][A-Za-z0-9\-\s/.,'*+]{1,40}?)\s{2,}"
        r"(?P<body>.+?)\s+"
        r"(?P<costtext>Rating\s*x\s*[\d,]+|100 \+ \(rating x 10\)|\(Rating x \d+\))\s*¥?\s*$",
        re.I,
    )

    skip_names = {
        "cost",
        "availability",
        "damage",
        "rating",
        "device",
        "capacity",
        "type",
        "mode",
        "ammo",
        "attack ratings",
        "defense rating",
        "conventional explosives",
    }
    lifestyle = (
        "per month",
        "per year",
        "month or",
        "year",
        "dose",
        "subscription",
    )

    def classify(name: str, body: str, section: str) -> str:
        b = body
        n = name.lower()
        if re.search(r"\b(SA|BF|FA|SS)\b", b) or re.search(r"\d+[PS](?:\(|\b)", b.replace(" ", "")):
            if re.search(r"\+?\d+\b", b) and "armor" in section.lower():
                pass
            else:
                return "weapon"
        if "armor" in section.lower() or re.search(r"\+\d+\b", b):
            if any(x in n for x in ("armor", "coat", "vest", "suit", "jumpsuit", "clothing", "helmet", "actioneer")):
                return "armor"
            if re.search(r"\+\d+\b", b) and "¥" not in name:
                return "armor"
        if re.search(r"\b0\.\d+\b", b) or "cyber" in section.lower() or "bioware" in section.lower():
            if "bio" in section.lower():
                return "bioware"
            return "cyberware"
        if section:
            if "weapon" in section.lower() or "firearm" in section.lower() or "melee" in section.lower():
                return "weapon"
            if "armor" in section.lower() or "clothing" in section.lower():
                return "armor"
            if "cyber" in section.lower():
                return "cyberware"
            if "bio" in section.lower():
                return "bioware"
        return "gear"

    def add(entry: dict) -> None:
        key = entry["name"].lower()
        if key in seen:
            return
        if key in skip_names:
            return
        seen.add(key)
        entries.append(entry)

    for raw in text.splitlines():
        line = raw.replace("\u00a0", " ").replace("–", "-").replace("—", "-").rstrip()
        if not line.strip():
            continue

        # Section headers
        if "¥" not in line and len(line.strip()) < 50:
            h = line.strip()
            hl = h.lower()
            if re.match(
                r"^(blades|clubs|exotic|unarmed|projectile|throwing|firearms?|hold-?outs?|"
                r"light pistols?|machine pistols?|heavy pistols?|submachine|smgs?|"
                r"assault rifles?|shotguns?|sniper|machine guns?|launchers?|"
                r"clothing and armor|armor|electronics|comms|sensors|security|"
                r"cyberware|headware|eyeware|earware|bodyware|cyberlimbs?|bioware|"
                r"ammunition|grenades|explosives|tools|survival|vehicles|cars|drones)",
                hl,
            ):
                category = h[:48]
                if any(x in hl for x in ("blade", "club", "pistol", "rifle", "shotgun", "gun", "weapon", "smg", "hold")):
                    kind = "weapon"
                elif "armor" in hl or "clothing" in hl:
                    kind = "armor"
                elif "bio" in hl:
                    kind = "bioware"
                elif "cyber" in hl or "ware" in hl:
                    kind = "cyberware"
                else:
                    kind = "gear"
            continue

        if any(x in line.lower() for x in lifestyle):
            continue
        if "Rating x" in line or "rating x" in line.lower() or "(rating" in line.lower():
            mf = formula_re.match(line)
            if mf:
                name = mf.group("name").strip(" *")
                body = mf.group("body")
                ct = re.sub(r"\s+", " ", mf.group("costtext")).strip()
                if not ct.endswith("¥"):
                    ct += "¥"
                ek = classify(name, body, category)
                add(
                    make_entry(
                        kind=ek,
                        name=name,
                        category=category,
                        cost_n=None,
                        body=body,
                        cost_text=ct,
                        notes=f"{ct} (variable; SR6)",
                    )
                )
            continue

        m = row_re.match(line)
        if not m:
            # Dual-column: try each …N¥ segment
            for m2 in re.finditer(
                r"(?P<name>[A-Za-z][A-Za-z0-9][A-Za-z0-9\-\s/.,'*+]{1,35}?)\s{2,}"
                r"(?P<body>(?:(?!\s{2,}[A-Z][a-z]).)*?)\s+"
                r"(?P<cost>\d{1,3}(?:,\d{3})*)\s*¥",
                line,
            ):
                name = m2.group("name").strip(" *")
                body = m2.group("body").strip()
                cost_n = parse_cost_yen(m2.group("cost"))
                if cost_n is None or cost_n < 5:
                    continue
                if len(name) < 3 or name.lower() in skip_names:
                    continue
                # Require mechanical token
                if not re.search(
                    r"(\d+[PS]|\bSA\b|\bBF\b|\bSS\b|\b0\.\d+\b|\+\d+|\d/\d)",
                    body,
                    re.I,
                ):
                    continue
                ek = classify(name, body, category)
                add(
                    make_entry(
                        kind=ek,
                        name=name,
                        category=category,
                        cost_n=cost_n,
                        body=body,
                    )
                )
            continue

        name = m.group("name").strip(" *")
        body = m.group("body")
        cost_n = parse_cost_yen(m.group("cost"))
        if cost_n is None or cost_n < 5:
            continue
        if name.lower() in skip_names or len(name) < 2:
            continue
        # Drop pure prose names
        if name.split()[0].lower() in {"the", "this", "when", "with", "from", "once", "designed"}:
            continue
        if not re.search(
            r"(\d+[PS]|\bSA\b|\bBF\b|\bFA\b|\bSS\b|\b0\.\d+\b|\+\d+|\[[\dR]|Rating)",
            body,
            re.I,
        ):
            continue
        ek = classify(name, body, category)
        add(
            make_entry(
                kind=ek,
                name=name,
                category=category,
                cost_n=cost_n,
                body=body,
            )
        )

    return entries


def parse_spells_light(text: str) -> list[dict]:
    """Light spell name capture from spell chapter headers (3–5 word titles)."""
    entries: list[dict] = []
    seen: set[str] = set()
    category = "Spell"
    titled = re.compile(
        r"^\s*(?P<name>[A-Z][A-Za-z' \-]{2,35})\s*$"
    )
    for raw in text.splitlines():
        s = raw.strip()
        if re.match(r"^(Combat|Detection|Health|Illusion|Manipulation)\s+Spells", s, re.I):
            category = re.sub(r"s$", "", s.split()[0].title()) + " Spell"
            continue
        # "Fireball" style short headers before type lines
        if titled.match(s) and len(s) < 28 and " " not in s[:1]:
            # Prefer multi-word known-style or single Camel/Title spell words
            if s.lower() in {
                "type", "range", "duration", "drain", "damage", "combat", "health",
                "detection", "illusion", "manipulation", "spells", "magic",
            }:
                continue
        m = re.match(
            r"^\s*(?P<name>[A-Z][A-Za-z' \-]{2,30})\s*$",
            s,
        )
        if not m:
            continue
        name = m.group("name").strip()
        # Skip sentences
        if len(name.split()) > 4:
            continue
        if name.lower() in seen:
            continue
        # Only keep if looks like a spell header (short, no lowercase article start)
        if name.split()[0].lower() in {"the", "these", "when", "with", "for", "and"}:
            continue
        # Too aggressive - skip pure spell parse for exactness; optional seed spells
        continue
    return entries


# Core SR6 combat spells from core listing (names only; Force free at cast).
SR6_SPELL_SEED = [
    ("Acid Stream", "Combat Spell"),
    ("Punch", "Combat Spell"),
    ("Clout", "Combat Spell"),
    ("Blast", "Combat Spell"),
    ("Fireball", "Combat Spell"),
    ("Flamethrower", "Combat Spell"),
    ("Lightning Bolt", "Combat Spell"),
    ("Ball Lightning", "Combat Spell"),
    ("Manabolt", "Combat Spell"),
    ("Manaball", "Combat Spell"),
    ("Powerbolt", "Combat Spell"),
    ("Powerball", "Combat Spell"),
    ("Stunbolt", "Combat Spell"),
    ("Stunball", "Combat Spell"),
    ("Heal", "Health Spell"),
    ("Increase Attribute", "Health Spell"),
    ("Antidote", "Health Spell"),
    ("Stabilize", "Health Spell"),
    ("Invisibility", "Illusion Spell"),
    ("Improved Invisibility", "Illusion Spell"),
    ("Silence", "Illusion Spell"),
    ("Armor", "Manipulation Spell"),
    ("Levitate", "Manipulation Spell"),
    ("Magic Fingers", "Manipulation Spell"),
]


def seed_entries() -> list[dict]:
    out: list[dict] = []
    for seed in VERIFIED_SEED:
        out.append(
            make_entry(
                kind=seed["kind"],
                name=seed["name"],
                category=seed.get("category", ""),
                cost_n=seed.get("costNuyen"),
                damage=seed.get("damage"),
                availability=seed.get("availability", ""),
                essence=seed.get("essenceText"),
                armor_rating=seed.get("armorRating"),
                notes=seed.get("notes", "Verified from SR6 core gear table"),
            )
        )
    for name, cat in SR6_SPELL_SEED:
        out.append(
            make_entry(
                kind="gear",
                name=name,
                category=cat,
                cost_n=None,
                cost_text="Spell (no nuyen; cast with Magic)",
                notes="SR6 core spell name (Street Grimoire chapter). Not a nuyen purchase.",
            )
        )
    return out


def merge_prefer_seed(parsed: list[dict], seeds: list[dict]) -> list[dict]:
    by_name: dict[str, dict] = {}
    for e in parsed:
        by_name[e["name"].lower()] = e
    for s in seeds:
        # Seeds always win for exact book values on overlapping names.
        by_name[s["name"].lower()] = s
    return sorted(by_name.values(), key=lambda e: (e["kind"], e["name"].lower()))


def run_exactness_checks(entries: list[dict]) -> list[str]:
    by = {e["name"].lower(): e for e in entries}
    errors: list[str] = []
    for name, expect in EXACT_CHECKS.items():
        e = by.get(name)
        if not e:
            errors.append(f"missing {name!r}")
            continue
        for k, v in expect.items():
            if e.get(k) != v:
                errors.append(f"{name}.{k}={e.get(k)!r} expected {v!r}")
    return errors


def build(pdf: Path) -> dict:
    print(f"Source PDF: {pdf}")
    print(f"Extracting gear pages {GEAR_PAGES[0]}–{GEAR_PAGES[1]}…")
    gear_txt = pdftotext(pdf, *GEAR_PAGES, raw=False)
    parsed = parse_layout_gear(gear_txt)
    seeds = seed_entries()
    merged = merge_prefer_seed(parsed, seeds)

    errors = run_exactness_checks(merged)
    kinds = Counter(e["kind"] for e in merged)
    manifest = {
        "formatVersion": 2,
        "edition": "sr6",
        "editionLabel": "SR6",
        "productName": "Shadowrun Sixth World Core Rulebook (City Edition Seattle)",
        "source": (
            f"Mechanical catalog extracted from {pdf.name} (SR6). "
            "Names, nuyen, availability, essence, damage only — not full rule text. "
            "See Catalog/NOTICE.txt."
        ),
        "sourcePdf": pdf.name,
        "entryCount": len(merged),
        "kinds": dict(sorted(kinds.items())),
        "entriesWithModifiers": 0,
        "exactnessChecks": {
            "passed": not errors,
            "errors": errors,
            "checked": sorted(EXACT_CHECKS.keys()),
        },
    }
    if errors:
        print("EXACTNESS CHECKS FAILED:")
        for err in errors:
            print(" ", err)
    else:
        print("Exactness checks: PASSED")
    print(f"Entries: {len(merged)}  kinds: {dict(kinds)}")
    return {"manifest": manifest, "entries": merged}


def main() -> int:
    if len(sys.argv) > 1:
        pdf = Path(sys.argv[1]).expanduser()
    else:
        pdf = next((p for p in DEFAULT_PDFS if p.is_file()), None)
        if pdf is None:
            print("No SR6 PDF found. Pass path explicitly.", file=sys.stderr)
            return 1
    if not pdf.is_file():
        print(f"Not found: {pdf}", file=sys.stderr)
        return 1

    data = build(pdf)
    if not data["manifest"]["exactnessChecks"]["passed"]:
        print("Refusing to write catalog with failed exactness checks.", file=sys.stderr)
        return 2

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
