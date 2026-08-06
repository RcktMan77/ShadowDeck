#!/usr/bin/env python3
"""
Build ShadowDeck/Resources/Catalog/sr4_catalog.json from the SR4A core PDF.

Preferred source (matches ShadowDeck's 400 BP / SR4A orientation):
  ~/Documents/eBooks/Shadowrun/20th-anniversary-core-rulebook.pdf

Fallback:
  ~/Documents/eBooks/Shadowrun/Shadowrun 4th Edition Core Book.pdf

Usage:
  python3 Scripts/build_sr4_catalog_from_pdf.py [path/to/rulebook.pdf]

Requires: pdftotext (poppler).

Copyright note: Extracted mechanical tables (names, costs, availability, page)
for offline companion use. Full rule text is NOT redistributed. Game content
remains property of its rights holders. ShadowDeck is unofficial and unaffiliated
with Catalyst Game Labs. See Resources/Catalog/NOTICE.txt.
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
OUT = ROOT / "ShadowDeck" / "Resources" / "Catalog" / "sr4_catalog.json"

DEFAULT_PDFS = [
    Path.home() / "Documents/eBooks/Shadowrun/20th-anniversary-core-rulebook.pdf",
    Path.home() / "Documents/eBooks/Shadowrun/Shadowrun 4th Edition Core Book.pdf",
]

# SR4A printed page → approximate PDF page (cover offset ~2 for 20th Ann.).
# Ranges are inclusive PDF pages for pdftotext -f/-l.
# PDF page indices (≈ printed page + 2 for this file).
SR4A_RANGES = {
    "chargen": (82, 100),
    "skills": (118, 132),
    "magic": (187, 200),
    "spells": (204, 214),  # Street Grimoire spell listings
    "gear": (317, 378),  # Street Gear stat tables (skip lifestyle costs intro)
}

# Original 2005 core (different pagination); used only if source is not 20th Ann.
SR4_2005_RANGES = {
    "chargen": (70, 95),
    "skills": (100, 130),
    "magic": (163, 195),
    "spells": (194, 210),
    "gear": (300, 354),
}

# Canonical skill groups (SR4A Skills chapter).
SKILL_GROUPS: list[tuple[str, str, list[str]]] = [
    ("athletics", "Athletics", ["Climbing", "Gymnastics", "Running", "Swimming"]),
    ("biotech", "Biotech", ["Cybertechnology", "First Aid", "Medicine"]),
    ("close_combat", "Close Combat", ["Blades", "Clubs", "Unarmed Combat"]),
    ("conjuring", "Conjuring", ["Banishing", "Binding", "Summoning"]),
    ("cracking", "Cracking", ["Cybercombat", "Electronic Warfare", "Hacking"]),
    ("electronics", "Electronics", ["Computer", "Data Search", "Hardware", "Software"]),
    ("firearms", "Firearms", ["Automatics", "Longarms", "Pistols"]),
    ("influence", "Influence", ["Con", "Etiquette", "Leadership", "Negotiation"]),
    ("outdoors", "Outdoors", ["Navigation", "Survival", "Tracking"]),
    ("sorcery", "Sorcery", ["Counterspelling", "Ritual Spellcasting", "Spellcasting"]),
    ("stealth", "Stealth", ["Disguise", "Infiltration", "Palming", "Shadowing"]),
    ("tasking", "Tasking", ["Compiling", "Decompiling", "Registering"]),
]

# Contact role seeds (freeform contacts; roles for picker UX).
CONTACT_ROLES = [
    "Fixer", "Johnson", "Talismonger", "Street Doc", "Fence", "Smuggler",
    "Bartender", "Beat Cop", "Detective", "Mafia Underboss", "Yakuza Contact",
    "Gang Leader", "Decker", "Rigger Mechanic", "Armorer", "Corp Secretary",
    "Reporter", "Bouncer", "Taxi Driver", "Landlord",
]

# BP formulas verified from SR4A chargen (Creating a Shadowrunner).
BP_RULES = {
    "budgetDefault": 400,
    "metatype": {"human": 0, "ork": 20, "dwarf": 25, "elf": 30, "troll": 40},
    "attributePointBP": 10,
    "activeSkillRankBP": 4,
    "knowledgeSkillPointBP": 2,
    "skillGroupRankBP": 10,
    "skillGroupMaxAtChargen": 4,
    "specializationBP": 2,
    "knowledgeSpecializationBP": 1,
    "spellBP": 3,
    "complexFormBPPerRating": 1,
    "contactBP": "connection + loyalty",
    "boundSpiritBP": "services owed",
    "focusBondBP": "force of focus",
    "nuyenPerBP": 5000,
    "positiveQualityCapBP": 35,
    "negativeQualityCapBP": 35,
    "maxActiveSkillRatingChargen": 6,
    "onlyOneActiveSkillAtSix": True,
    "sourceChapter": "Creating a Shadowrunner (SR4A / 20th Anniversary Core)",
    "edition": "SR4A",
    "notEdition": "SR4E is not a Catalyst product code; this book is SR4A (20th Anniversary).",
}


def stable_id(kind: str, name: str, category: str = "") -> str:
    raw = f"sr4|{kind}|{category}|{name}".lower().encode()
    h = hashlib.sha1(raw).hexdigest()
    # Deterministic UUID-like id (not RFC random).
    return str(uuid.UUID(h[:32]))


def pdftotext(pdf: Path, start: int, end: int, raw: bool = True) -> str:
    args = ["pdftotext"]
    if raw:
        args.append("-raw")
    else:
        args.append("-layout")
    args += ["-f", str(start), "-l", str(end), str(pdf), "-"]
    r = subprocess.run(args, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise RuntimeError(r.stderr or f"pdftotext failed for pages {start}-{end}")
    return r.stdout


def humanize_name(name: str) -> str:
    """Turn CamelCase or glued names into readable titles."""
    s = name.strip()
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", s)
    s = re.sub(r"(\d)([A-Za-z])", r"\1 \2", s)
    s = re.sub(r"([A-Za-z])(\d)", r"\1 \2", s)
    s = re.sub(r"\s+", " ", s).strip()
    # Keep known acronyms / model bits sensible
    return s


def parse_cost_yen(s: str) -> int | None:
    s = (s or "").strip().replace(",", "").replace("¥", "").replace("Y", "")
    if not s or any(c in s for c in "+*/~–—"):
        # ranges like 50-1000 skip fixed cost
        if re.fullmatch(r"\d+", s):
            return int(s)
        return None
    try:
        return int(s)
    except ValueError:
        return None


def _make_entry(
    *,
    kind: str,
    name: str,
    category: str,
    cost_n: int | None,
    cost_text: str,
    body: str,
    source: str = "SR4A",
    karma: int | None = None,
) -> dict:
    avail_m = re.search(r"(\d{1,2}[RF])\b", body)
    damage_m = re.search(
        r"((?:STR/2(?:\s*\+\s*\d+)?|\d+)[PS](?:\([ef]\))?)",
        body.replace(" ", ""),
    )
    armor_m = re.search(r"(\d+)\s*/\s*(\d+)", body)
    # Essence may be fractional (0.1) or whole (Wired Reflexes Rating 1 = 2).
    essence_m = re.search(r"\b(0\.\d+|[1-6](?:\.\d+)?)\b", body)
    armor_rating = int(armor_m.group(1)) if kind == "armor" and armor_m else None
    essence = None
    if kind in {"cyberware", "bioware"} and essence_m:
        # Prefer leading essence-like token in body (first number in cyber tables).
        lead = re.match(r"^\s*([0-6](?:\.\d+)?)\b", body)
        essence = lead.group(1) if lead else essence_m.group(1)
    return {
        "id": stable_id(kind, name, category),
        "kind": kind,
        "name": name,
        "category": category,
        "costText": cost_text,
        "costNuyen": cost_n,
        "availability": avail_m.group(1) if avail_m else "",
        "source": source,
        "page": "",
        "essenceText": essence,
        "karma": karma,
        "damage": damage_m.group(1) if damage_m else None,
        "armorRating": armor_rating,
        "notes": re.sub(r"\s+", " ", body).strip()[:160],
        "modifiers": [],
    }


def parse_gear_tables(text: str, default_kind: str = "gear") -> list[dict]:
    """
    Parse Street Gear **layout** tables (pdftotext -layout) from SR4A.

    Prefers fixed nuyen costs. Skips lifestyle services, Rating× formulas, and ranges.
    Tracks parent headers so 'Rating 1' rows become 'Cybereyes Basic System (Rating 1)'.
    """
    entries: list[dict] = []
    seen: set[str] = set()

    # Primary: name … body … cost¥  (name starts after optional indent)
    single_re = re.compile(
        r"^(?P<indent>\s*)(?P<name>[A-Z][A-Za-z0-9][A-Za-z0-9\-\s/\'.,+]{0,48}?)"
        r"(?P<gap>\s{2,})"
        r"(?P<body>.+?)"
        r"\s+(?P<cost>\d{1,3}(?:,\d{3})*)\s*¥\s*$"
    )
    rating_re = re.compile(
        r"^(?P<indent>\s{2,})Rating\s+(?P<r>\d)\s+"
        r"(?P<body>.+?)\s+(?P<cost>\d{1,3}(?:,\d{3})*)\s*¥\s*$"
    )
    # Variable cost rows we still want named with text cost only
    formula_re = re.compile(
        r"^(?P<indent>\s*)(?P<name>[A-Z][A-Za-z0-9][A-Za-z0-9\-\s/\'.,+]{0,48}?)"
        r"\s{2,}(?P<body>.+?)\s+"
        r"(?P<costtext>Rating\s*x\s*[\d,]+)\s*¥\s*$",
        re.I,
    )

    skip_names = {
        "cost", "availability", "damage", "armor", "essence", "capacity", "avail",
        "clothing", "helmets and shields", "ballistic", "impact",
    }
    lifestyle_bits = (
        "per hour", "per day", "per week", "per minute", "per 1 km", "per 10 km",
        "meal", "drinks", "taxi", "hotel", "hostel", "motel", "rental", "parking",
        "fare", "prostitute", "escort", "safehouse", "insurance", "bodyguard",
        "vending", "nightclub", "admission", "performance", "season ticket",
        "commuter", "suborbital", "dataterm", "private room", "coffin",
    )

    kind = default_kind
    category = "Street Gear"
    parent_name = ""
    parent_kind = kind

    def classify(name: str, body: str, section_kind: str) -> str:
        b = body
        b_compact = re.sub(r"\s+", "", b)
        nlow = name.lower()
        if re.search(r"\b(Under|Barrel|Top|Internal|External)\b", b) or any(
            x in nlow
            for x in (
                "silencer",
                "suppressor",
                "holster",
                "bipod",
                "tripod",
                "laser sight",
                "imaging scope",
                "gas-vent",
                "gyro",
                "smart firing",
                "airburst",
                "shock pad",
                "spare clip",
                "speed loader",
            )
        ):
            return "gear"  # weapon accessory / modification
        if re.search(r"\b(SA|BF|FA|SS)\b", b) or re.search(
            r"(?:\d+P|\d+S|STR/2)", b_compact
        ):
            return "weapon"
        if re.search(r"\d+\s*/\s*\d+", b) and "0." not in b:
            return "armor"
        if re.search(r"\b0\.\d+\b", b) or "essence" in category.lower():
            return "bioware" if "bio" in category.lower() else "cyberware"
        if section_kind in {"weapon", "armor", "cyberware", "bioware", "gear"}:
            return section_kind
        return "gear"

    def add(name: str, body: str, cost_n: int | None, cost_text: str, entry_kind: str) -> None:
        name = re.sub(r"\s+", " ", name).strip(" -:")
        if not name or name.lower() in skip_names or len(name) < 2:
            return
        if any(x in name.lower() for x in lifestyle_bits) or any(
            x in body.lower() for x in lifestyle_bits
        ):
            return
        key = (entry_kind, name.lower())
        if key in seen:
            return
        seen.add(key)
        entries.append(
            _make_entry(
                kind=entry_kind,
                name=name,
                category=category,
                cost_n=cost_n,
                cost_text=cost_text,
                body=body,
            )
        )

    for raw in text.splitlines():
        line = raw.replace("\u00a0", " ").replace("–", "-").replace("—", "-").rstrip()
        if not line.strip() or "STREET GEAR" in line:
            continue

        # Section headers (short title lines without yen)
        if "¥" not in line and len(line.strip()) < 48:
            h = line.strip().lower()
            if re.match(
                r"^(blades|clubs|exotic melee|unarmed|projectile|throwing|bows?|firearms|"
                r"pistols|tasers|machine pistols|submachine guns|assault rifles|sniper rifles|"
                r"shotguns|machine guns|launchers|heavy weapons|melee)",
                h,
            ):
                kind, category, parent_name = "weapon", line.strip()[:48], ""
            elif re.match(r"^(armor|clothing|helmets?|shields?)\b", h):
                kind, category, parent_name = "armor", line.strip()[:48], ""
            elif re.match(
                r"^(cyberware|headware|eyeware|earware|bodyware|cyberlimbs?|augmentation)",
                h,
            ):
                kind, category, parent_name = "cyberware", line.strip()[:48], ""
            elif re.match(r"^(bioware|cultured bioware)\b", h):
                kind, category, parent_name = "bioware", line.strip()[:48], ""
            elif re.match(
                r"^(ammunition|grenades|explosives|electronics|comms|sensors|security|"
                r"tools|survival|chemicals|vehicles|drones|commlinks|weapon accessories|"
                r"audio|visual)",
                h,
            ):
                kind, category, parent_name = "gear", line.strip()[:48], ""
            elif re.match(r"^[A-Z][A-Za-z0-9 \-/]{2,40}$", line.strip()) and not re.search(
                r"\d", line
            ):
                # Possible parent system name (Cybereyes Basic System, Wired Reflexes)
                parent_name = line.strip()
                parent_kind = kind
            continue

        if "Rating x" in line or "rating x" in line.lower():
            mform = formula_re.match(line)
            if mform:
                name = mform.group("name").strip()
                body = mform.group("body")
                ct = mform.group("costtext").replace(" ", "")
                ek = classify(name, body, kind)
                add(name, body, None, ct + "¥", ek)
            continue

        mr = rating_re.match(line)
        if mr:
            r = mr.group("r")
            body = mr.group("body")
            cost_n = parse_cost_yen(mr.group("cost"))
            base = parent_name or "System"
            name = f"{base} (Rating {r})"
            ek = parent_kind if parent_name else classify(name, body, kind)
            if cost_n is not None:
                add(name, body, cost_n, f"¥{cost_n}", ek)
            continue

        # Dual-column lines: split on each …N¥ chunk from the right repeatedly
        # Prefer full-line single match first.
        ms = single_re.match(line)
        if ms and line.count("¥") == 1:
            name = ms.group("name").strip()
            # Crossbow size rows alone
            if name.lower() in {"light", "medium", "heavy", "bolt", "arrow"}:
                if parent_name:
                    name = f"{parent_name} ({name})"
                else:
                    continue
            body = ms.group("body")
            cost_n = parse_cost_yen(ms.group("cost"))
            if cost_n is None:
                continue
            if cost_n < 5:
                continue
            ek = classify(name, body, kind)
            # Remember parents for systems that list plain names then ratings
            if re.search(r"basic system|wired reflexes|cyberears|cybereyes", name, re.I):
                parent_name = name
                parent_kind = ek
            add(name, body, cost_n, f"¥{cost_n}", ek)
            continue

        # Multi-yen line: extract all fixed-cost trailing segments
        if line.count("¥") >= 1:
            # Find all "Name  body  cost¥" segments with at least 2 spaces before bodyish
            for m in re.finditer(
                r"(?P<name>[A-Z][A-Za-z0-9][A-Za-z0-9\-\s/\'.,+]{1,40}?)\s{2,}"
                r"(?P<body>(?:(?!\s{2,}[A-Z]).)*?)\s+"
                r"(?P<cost>\d{1,3}(?:,\d{3})*)\s*¥",
                line,
            ):
                name = m.group("name").strip()
                body = m.group("body").strip()
                if "Rating x" in body or "Rating x" in name:
                    continue
                cost_n = parse_cost_yen(m.group("cost"))
                if cost_n is None or cost_n < 5:
                    continue
                # Skip ranges like 20-100
                if re.search(r"\d+\s*-\s*\d+", m.group(0)):
                    continue
                ek = classify(name, body, kind)
                add(name, body, cost_n, f"¥{cost_n}", ek)

    return entries


def parse_qualities(text: str) -> list[dict]:
    """Extract positive/negative qualities with BP cost/bonus from chargen chapter."""
    entries: list[dict] = []
    seen: set[str] = set()

    # Split-ish: quality name lines followed by Cost: or Bonus:
    # Patterns in raw extract are messy; use Cost:/Bonus: anchors and look backward for a title.
    lines = [re.sub(r"\s+", " ", ln).strip() for ln in text.splitlines() if ln.strip()]

    cost_re = re.compile(
        r"^(?:Cost|Bonus):\s*(\d+)(?:\s*to\s*(\d+))?\s*BP(?:\s*per\s*rating)?",
        re.I,
    )
    # "Cost: 5 or 10 BP"
    cost_or_re = re.compile(r"^(?:Cost|Bonus):\s*(\d+)\s+or\s+(\d+)\s*BP", re.I)
    # "Cost: 10 BP per rating (max rating 2)"
    name_re = re.compile(r"^[A-Z][A-Za-z][A-Za-z \-/'()]{1,40}$")

    for i, line in enumerate(lines):
        m = cost_or_re.match(line) or cost_re.match(line)
        if not m:
            # Inline "QualityName Cost: 10 BP"
            inline = re.search(
                r"([A-Z][A-Za-z][A-Za-z \-/'()]{2,35})\s+(?:Cost|Bonus):\s*(\d+)(?:\s*or\s*(\d+))?\s*BP",
                line,
            )
            if not inline:
                continue
            name = inline.group(1).strip()
            bp = int(inline.group(2))
            is_bonus = "bonus:" in line.lower()
        else:
            bp = int(m.group(1))
            is_bonus = line.lower().startswith("bonus")
            # Look back for name
            name = None
            for j in range(i - 1, max(-1, i - 6), -1):
                cand = lines[j]
                if cost_re.match(cand) or cost_or_re.match(cand):
                    continue
                if cand.lower().startswith(("a character", "characters", "this quality", "the ", "for every", "note")):
                    continue
                # Title-ish last token group
                # Often "Adept" or "Magician" alone on a line
                short = cand
                if len(short) > 50:
                    # take trailing capitalized phrase
                    mm = re.search(r"([A-Z][A-Za-z][A-Za-z \-/'()]{1,40})$", short)
                    short = mm.group(1) if mm else short[:40]
                if name_re.match(short) or (len(short) <= 40 and short[0].isupper()):
                    name = short
                    break
            if not name:
                continue

        name = re.sub(r"\s+", " ", name).strip(" .:")
        if name.lower() in seen:
            continue
        if name.lower() in {"cost", "bonus", "positive qualities", "negative qualities", "qualities"}:
            continue
        seen.add(name.lower())

        # Positive = karma/cost field positive; negative qualities store positive magnitude with note
        karma = bp if not is_bonus else -bp
        entries.append(
            {
                "id": stable_id("quality", name),
                "kind": "quality",
                "name": name,
                "category": "Negative Quality" if is_bonus else "Positive Quality",
                "costText": f"{abs(bp)} BP",
                "costNuyen": None,
                "availability": "",
                "source": "SR4A",
                "page": "",
                "essenceText": None,
                "karma": karma,  # BP at chargen; field reused for cost magnitude
                "damage": None,
                "armorRating": None,
                "notes": "Chargen BP " + ("bonus (negative quality)" if is_bonus else "cost (positive quality)"),
                "modifiers": [],
            }
        )
    return entries


def parse_spells(text: str) -> list[dict]:
    """
    Extract spell names from SR4A Street Grimoire **layout** text.

    Category follows last section header (Combat/Detection/Health/Illusion/Manipulation Spells).
    Captures 'Name (Direct/Indirect/…)' headers and short names immediately above Type: lines.
    """
    entries: list[dict] = []
    seen: set[str] = set()
    category = "Spell"
    pending_name: str | None = None

    header_re = re.compile(
        r"^(Combat|Detection|Health|Illusion|Manipulation)\s+Spells\b",
        re.I,
    )
    titled = re.compile(
        r"^(?P<name>[A-Z][A-Za-z0-9' \-]{2,40}?)\s*\("
        r"(?P<tags>[^)]*(?:Direct|Indirect|Elemental|Area|Active|Passive|Directional|Psychic|"
        r"Realistic|Obvious|Single-Sense|Multi-Sense|Physical|Mana)[^)]*)\)\s*$"
    )
    type_line = re.compile(r"^Type:\s*", re.I)
    short_name = re.compile(r"^(?P<name>[A-Z][A-Za-z0-9' \-]{2,35})$")

    def emit(name: str) -> None:
        name = re.sub(r"\s+", " ", name).strip(" -:")
        if len(name) < 3 or len(name) > 40:
            return
        if name.lower() in {
            "type", "range", "damage", "duration", "drain", "spell", "combat",
            "detection", "health", "illusion", "manipulation", "physical", "mana",
            "direct combat spells", "indirect combat spells", "elemental effects",
            "negative health spells", "healing characters with implants",
        }:
            return
        if name.lower().startswith(("the ", "this ", "when ", "note ", "see ")):
            return
        if name.lower() in seen:
            return
        seen.add(name.lower())
        entries.append(
            {
                "id": stable_id("gear", name, "spell"),
                "kind": "gear",
                "name": name,
                "category": category,
                "costText": "3 BP (chargen)",
                "costNuyen": None,
                "availability": "",
                "source": "SR4A",
                "page": "",
                "essenceText": None,
                "karma": 3,
                "damage": None,
                "armorRating": None,
                "notes": (
                    "SR4A chargen: 3 BP per spell. "
                    "Max spells = 2 × highest Spellcasting or Ritual Spellcasting."
                ),
                "modifiers": [],
            }
        )

    for raw in text.splitlines():
        # Layout may put two columns on one line — process each ~half when possible
        chunks = [raw]
        if len(raw) > 90 and re.search(r"\s{4,}", raw[40:]):
            # soft split on large gap near middle
            m = re.search(r".{30}?\s{4,}(.+)$", raw)
            if m:
                left = raw[: m.start(1)].rstrip()
                right = m.group(1).strip()
                chunks = [left, right]

        for s in chunks:
            s = s.strip()
            if not s:
                continue
            hm = header_re.match(s)
            if hm:
                category = f"{hm.group(1).title()} Spell"
                pending_name = None
                continue
            # Also match headers embedded after spaces
            hm2 = re.search(
                r"\b(Combat|Detection|Health|Illusion|Manipulation)\s+Spells\b", s, re.I
            )
            if hm2 and len(s) < 60:
                category = f"{hm2.group(1).title()} Spell"
                pending_name = None
                continue

            tm = titled.match(s)
            if tm:
                emit(tm.group("name"))
                pending_name = None
                continue

            if type_line.match(s):
                if pending_name:
                    emit(pending_name)
                    pending_name = None
                continue

            # Standalone title line (Heal, Manabolt) — may be followed by Type:
            if short_name.match(s) and ":" not in s and len(s) < 36:
                # Don't treat section words as spells
                if s.lower() not in {
                    "combat spells",
                    "detection spells",
                    "health spells",
                    "illusion spells",
                    "manipulation spells",
                    "street grimoire",
                    "spell characteristics",
                }:
                    pending_name = s
                continue

            pending_name = None

    return entries


def parse_adept_powers(text: str) -> list[dict]:
    entries: list[dict] = []
    seen: set[str] = set()
    # Cost:.25perlevel near power names — hard. Curate common SR4A powers + any Cost: lines.
    curated = [
        ("Improved Reflexes", "Variable PP by level", "1 / 2 / 3 PP for rating 1–3"),
        ("Improved Ability", ".5 combat / .25 other per level", "Skill boost"),
        ("Critical Strike", ".25 per level", ""),
        ("Combat Sense", ".5 per level", ""),
        ("Mystic Armor", ".5 per level", ""),
        ("Pain Resistance", ".5 per level", ""),
        ("Killing Hands", ".5", ""),
        ("Astral Perception", "1", ""),
        ("Improved Sense", ".25 per improvement", ""),
        ("Attribute Boost", ".25 per level", ""),
        ("Great Leap", ".25 per level", ""),
        ("Traceless Walk", ".5", ""),
        ("Wall Running", ".5", ""),
        ("Natural Immunity", ".25 per level", ""),
        ("Rapid Healing", ".5 per level", ""),
        ("Spell Resistance", ".5 per level", ""),
        ("Voice Control", ".5", ""),
        ("Enhanced Perception", ".25 per level", ""),
        ("Motion Sense", ".5", ""),
        ("Flexibility", ".25 per level", ""),
    ]
    for name, cost, note in curated:
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        entries.append(
            {
                "id": stable_id("adeptPower", name),
                "kind": "adeptPower",
                "name": name,
                "category": "Adept Power",
                "costText": cost,
                "costNuyen": None,
                "availability": "",
                "source": "SR4A",
                "page": "",
                "essenceText": None,
                "karma": None,
                "damage": None,
                "armorRating": None,
                "notes": (note + " Paid with Power Points = Magic at chargen.").strip(),
                "modifiers": [],
            }
        )
    return entries


def skill_group_entries() -> list[dict]:
    out = []
    for key, name, members in SKILL_GROUPS:
        out.append(
            {
                "id": stable_id("skill", name, "skillGroup"),
                "kind": "skill",
                "name": name,
                "category": "Skill Group",
                "costText": "10 BP × rating (chargen max 4)",
                "costNuyen": None,
                "availability": "",
                "source": "SR4A",
                "page": "118",
                "essenceText": None,
                "karma": 10,  # BP per group point
                "damage": None,
                "armorRating": None,
                "notes": "Members: "
                + ", ".join(members)
                + ". Chargen: 10 BP per rating; max group rating 4. No specializations on groups at chargen.",
                "modifiers": [],
            }
        )
        for member in members:
            out.append(
                {
                    "id": stable_id("skill", member, key),
                    "kind": "skill",
                    "name": member,
                    "category": f"Active Skill ({name})",
                    "costText": "4 BP × rating",
                    "costNuyen": None,
                    "availability": "",
                    "source": "SR4A",
                    "page": "",
                    "essenceText": None,
                    "karma": 4,
                    "damage": None,
                    "armorRating": None,
                    "notes": f"Active skill in {name} group. Chargen: 4 BP per rating (max 6; only one skill at 6).",
                    "modifiers": [],
                }
            )
    return out


def contact_role_entries() -> list[dict]:
    out = []
    for role in CONTACT_ROLES:
        out.append(
            {
                "id": stable_id("contactRole", role),
                "kind": "contactRole",
                "name": role,
                "category": "Contact Role",
                "costText": "Connection + Loyalty BP",
                "costNuyen": None,
                "availability": "",
                "source": "SR4A",
                "page": "88",
                "essenceText": None,
                "karma": None,
                "damage": None,
                "armorRating": None,
                "notes": "Contact BP cost = Connection (1–6) + Loyalty (1–6). Role is flavor only.",
                "modifiers": [],
            }
        )
    return out


def meta_bp_entries() -> list[dict]:
    """Small reference rows for wizard/engine docs (not gear)."""
    rows = [
        ("Build Points Budget", "400 BP standard campaign", "budget"),
        ("Attribute Point", "10 BP per +1 above minimum", "attribute"),
        ("Active Skill Rank", "4 BP per rating", "skill"),
        ("Skill Group Rank", "10 BP per rating (max 4 at chargen)", "skillGroup"),
        ("Knowledge Skill Point", "2 BP per extra point beyond free pool", "knowledge"),
        ("Spell (chargen)", "3 BP per spell", "spell"),
        ("Complex Form (chargen)", "1 BP per rating point", "complexForm"),
        ("Contact", "Connection + Loyalty BP", "contact"),
        ("Resources", "1 BP = ¥5,000", "resources"),
        ("Positive Qualities Cap", "35 BP max spent", "quality"),
        ("Negative Qualities Cap", "35 BP max gained", "quality"),
    ]
    out = []
    for name, note, cat in rows:
        out.append(
            {
                "id": stable_id("gear", name, "bpRule"),
                "kind": "gear",
                "name": f"[BP] {name}",
                "category": f"BP Rule ({cat})",
                "costText": note,
                "costNuyen": 5000 if cat == "resources" else None,
                "availability": "",
                "source": "SR4A",
                "page": "80",
                "essenceText": None,
                "karma": None,
                "damage": None,
                "armorRating": None,
                "notes": note + " — Creating a Shadowrunner (SR4A).",
                "modifiers": [],
            }
        )
    return out


def detect_ranges(pdf: Path) -> dict[str, tuple[int, int]]:
    name = pdf.name.lower()
    if "20th" in name or "anniversary" in name:
        return SR4A_RANGES
    return SR4_2005_RANGES


def build(pdf: Path) -> dict:
    ranges = detect_ranges(pdf)
    is_sr4a = ranges is SR4A_RANGES
    source_label = "SR4A" if is_sr4a else "SR4"

    print(f"Source PDF: {pdf}")
    print(f"Edition profile: {source_label}")
    print("Extracting sections…")

    # Chargen/qualities: raw is denser; gear+spells: layout for exact table columns.
    chargen = pdftotext(pdf, *ranges["chargen"], raw=True)
    skills = pdftotext(pdf, *ranges["skills"], raw=True)
    spells_txt = pdftotext(pdf, *ranges["spells"], raw=False)
    gear_txt = pdftotext(pdf, *ranges["gear"], raw=False)
    try:
        adept_txt = pdftotext(pdf, *ranges.get("magic", (187, 195)), raw=True)
    except Exception:
        adept_txt = ""

    entries: list[dict] = []
    entries += skill_group_entries()
    entries += contact_role_entries()
    entries += meta_bp_entries()
    entries += parse_qualities(chargen)
    entries += parse_spells(spells_txt)
    entries += parse_adept_powers(adept_txt or skills)
    gear_entries = parse_gear_tables(gear_txt)
    for e in gear_entries:
        e["source"] = source_label
    entries += gear_entries

    # Dedupe by kind+name
    deduped: list[dict] = []
    seen: set[tuple[str, str]] = set()
    for e in entries:
        key = (e["kind"], e["name"].lower())
        if key in seen:
            continue
        seen.add(key)
        deduped.append(e)

    kinds = Counter(e["kind"] for e in deduped)
    # Spot-check known SR4A table values (fail loud if extraction drifted).
    by_name = {e["name"].lower(): e for e in deduped}
    checks = {
        "ares predator iv": {"costNuyen": 350, "kind": "weapon"},
        "armor vest": {"costNuyen": 600, "kind": "armor"},
        "datajack": {"costNuyen": 500, "kind": "cyberware"},
        "combat axe": {"costNuyen": 600, "kind": "weapon"},
        "katana": {"costNuyen": 1000, "kind": "weapon"},
        "fireball": {"karma": 3},
        "manabolt": {"karma": 3},
    }
    check_errors: list[str] = []
    for name, expect in checks.items():
        e = by_name.get(name)
        if not e:
            check_errors.append(f"missing {name!r}")
            continue
        for k, v in expect.items():
            if e.get(k) != v:
                check_errors.append(f"{name}.{k}={e.get(k)!r} expected {v!r}")

    manifest = {
        "formatVersion": 2,
        "edition": "sr4",
        "editionLabel": "SR4A",
        "productName": "Shadowrun 20th Anniversary Core Rulebook",
        "source": (
            f"Mechanical catalog extracted from {pdf.name} "
            f"(SR4A / 20th Anniversary — not original 2005 SR4). "
            f"Names, nuyen costs, availability, and BP chargen costs only — "
            f"not full rule text. See Catalog/NOTICE.txt."
        ),
        "sourcePdf": pdf.name,
        "bpRules": BP_RULES,
        "entryCount": len(deduped),
        "kinds": dict(sorted(kinds.items())),
        "entriesWithModifiers": 0,
        "exactnessChecks": {
            "passed": not check_errors,
            "errors": check_errors,
        },
    }
    if check_errors:
        print("WARNING: exactness checks failed:")
        for err in check_errors:
            print(" ", err)
    return {"manifest": manifest, "entries": deduped}


def main() -> int:
    if len(sys.argv) > 1:
        pdf = Path(sys.argv[1]).expanduser()
    else:
        pdf = next((p for p in DEFAULT_PDFS if p.is_file()), None)
        if pdf is None:
            print("No PDF found. Pass path to SR4A core rulebook.", file=sys.stderr)
            print("Tried:", *DEFAULT_PDFS, sep="\n  ", file=sys.stderr)
            return 1

    if not pdf.is_file():
        print(f"Not found: {pdf}", file=sys.stderr)
        return 1

    data = build(pdf)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    m = data["manifest"]
    print(f"Wrote {OUT}")
    print(f"Entries: {m['entryCount']}  kinds: {m['kinds']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
