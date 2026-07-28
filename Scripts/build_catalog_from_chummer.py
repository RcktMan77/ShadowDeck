#!/usr/bin/env python3
"""
Build ShadowDeck/Resources/Catalog/sr5_catalog.json from a Chummer5a data/ folder.

Usage:
  python3 Scripts/build_catalog_from_chummer.py /path/to/Chummer/data

Source data is GPL-3.0 (Chummer5a). See Resources/Catalog/NOTICE.txt.

Phase 7: extracts play-sheet modifiers from <bonus> nodes
(specificattribute, specificskill, armor, initiativepass, initiative, limitmodifier).
"""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def text(el: ET.Element, tag: str, default: str = "") -> str:
    n = el.find(tag)
    if n is None or n.text is None:
        return default
    return n.text.strip()


def parse_cost(s: str) -> int | None:
    s = (s or "").strip().replace(",", "")
    if not s:
        return None
    if any(c.isalpha() or c in "*+/" for c in s):
        return int(s) if s.isdigit() else None
    try:
        return int(s)
    except ValueError:
        return None


ATTR_MAP = {
    "BOD": "body",
    "BODY": "body",
    "AGI": "agility",
    "AGILITY": "agility",
    "REA": "reaction",
    "REACTION": "reaction",
    "STR": "strength",
    "STRENGTH": "strength",
    "WIL": "willpower",
    "WILLPOWER": "willpower",
    "LOG": "logic",
    "LOGIC": "logic",
    "INT": "intuition",
    "INTUITION": "intuition",
    "CHA": "charisma",
    "CHARISMA": "charisma",
    "EDG": "edge",
    "EDGE": "edge",
    "MAG": "magic",
    "MAGIC": "magic",
    "RES": "resonance",
    "RESONANCE": "resonance",
}


def parse_fixed_values(raw: str) -> list[int] | None:
    m = re.match(r"(?i)^FixedValues\((.+)\)$", (raw or "").strip())
    if not m:
        return None
    parts = [p.strip() for p in m.group(1).split(",")]
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return None
    return nums or None


def parse_amount(raw: str) -> dict | None:
    """Return modifier amount fields or None if unparseable / complex."""
    t = (raw or "").strip()
    if not t:
        return None
    table = parse_fixed_values(t)
    if table is not None:
        return {
            "amount": table[0],
            "usesRating": False,
            "ratingOffset": 0,
            "ratingTable": table,
        }
    if "{" in t or "number(" in t.lower():
        return None
    if t.lower() == "rating":
        return {"amount": 1, "usesRating": True, "ratingOffset": 0}
    if t.lower() == "-rating":
        return {"amount": -1, "usesRating": True, "ratingOffset": 0}
    m = re.match(r"(?i)^Rating\s*\*\s*(-?\d+)$", t)
    if m:
        return {"amount": int(m.group(1)), "usesRating": True, "ratingOffset": 0}
    m = re.match(r"(?i)^Rating\s*([+-]\d+)$", t)
    if m:
        return {"amount": 1, "usesRating": True, "ratingOffset": int(m.group(1))}
    try:
        return {"amount": int(t), "usesRating": False, "ratingOffset": 0}
    except ValueError:
        return None


def parse_bonuses(el: ET.Element) -> list[dict]:
    bonus = el.find("bonus")
    if bonus is None:
        return []
    out: list[dict] = []

    def add(
        target: str,
        parsed: dict,
        skill_key: str | None = None,
        condition: str | None = None,
    ):
        mod = {
            "target": target,
            "amount": parsed["amount"],
            "usesRating": parsed.get("usesRating", False),
        }
        if parsed.get("ratingOffset"):
            mod["ratingOffset"] = parsed["ratingOffset"]
        if parsed.get("ratingTable"):
            mod["ratingTable"] = parsed["ratingTable"]
        if skill_key:
            mod["skillKey"] = skill_key
        if condition:
            mod["condition"] = condition
        out.append(mod)

    for sa in bonus.findall("specificattribute"):
        name = text(sa, "name").upper()
        target = ATTR_MAP.get(name)
        if not target:
            continue
        parsed = parse_amount(text(sa, "val"))
        if parsed:
            add(target, parsed)

    for ss in bonus.findall("specificskill"):
        skill = text(ss, "name")
        if not skill:
            continue
        parsed = parse_amount(text(ss, "bonus"))
        if parsed:
            add("skill", parsed, skill_key=skill)

    for armor_el in bonus.findall("armor"):
        raw = (armor_el.text or "").strip()
        parsed = parse_amount(raw)
        if parsed:
            add("armor", parsed)

    for pass_el in bonus.findall("initiativepass"):
        raw = (pass_el.text or "").strip()
        parsed = parse_amount(raw)
        if parsed:
            add("initiativeDice", parsed)

    for init_el in bonus.findall("initiative"):
        raw = (init_el.text or "").strip()
        parsed = parse_amount(raw)
        if parsed:
            add("initiative", parsed)

    for lim in bonus.findall("limitmodifier"):
        limit = text(lim, "limit").lower()
        target = {
            "physical": "physicalLimit",
            "mental": "mentalLimit",
            "social": "socialLimit",
        }.get(limit)
        if not target:
            continue
        parsed = parse_amount(text(lim, "value"))
        if parsed:
            cond = text(lim, "condition") or None
            add(target, parsed, condition=cond)

    return out


def entries_from(
    data_dir: Path,
    file: str,
    element: str,
    kind: str,
    enrich=None,
) -> list[dict]:
    path = data_dir / file
    if not path.exists():
        print(f"missing {file}", file=sys.stderr)
        return []
    root = ET.parse(path).getroot()
    out: list[dict] = []
    for el in root.findall(f".//{element}"):
        name = text(el, "name")
        if not name:
            continue
        eid = text(el, "id") or f"{kind}:{name}"
        cost_text = text(el, "cost")
        entry = {
            "id": eid,
            "kind": kind,
            "name": name,
            "category": text(el, "category"),
            "costText": cost_text,
            "costNuyen": parse_cost(cost_text),
            "availability": text(el, "avail"),
            "source": text(el, "source"),
            "page": text(el, "page"),
            "essenceText": None,
            "karma": None,
            "damage": None,
            "armorRating": None,
            "notes": "",
            "modifiers": parse_bonuses(el),
        }
        if enrich:
            enrich(el, entry)
        out.append(entry)
    print(f"{file} {element} {len(out)}")
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    data_dir = Path(sys.argv[1]).expanduser().resolve()
    if not data_dir.is_dir():
        print(f"not a directory: {data_dir}", file=sys.stderr)
        return 2

    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "ShadowDeck" / "Resources" / "Catalog"
    out_dir.mkdir(parents=True, exist_ok=True)

    all_entries: list[dict] = []
    all_entries += entries_from(
        data_dir,
        "weapons.xml",
        "weapon",
        "weapon",
        lambda el, e: e.update(damage=text(el, "damage") or None),
    )
    all_entries += entries_from(
        data_dir,
        "armor.xml",
        "armor",
        "armor",
        lambda el, e: e.__setitem__(
            "armorRating", int(text(el, "armor")) if text(el, "armor").isdigit() else None
        ),
    )
    all_entries += entries_from(data_dir, "gear.xml", "gear", "gear")
    all_entries += entries_from(
        data_dir,
        "cyberware.xml",
        "cyberware",
        "cyberware",
        lambda el, e: e.__setitem__("essenceText", text(el, "ess") or None),
    )
    all_entries += entries_from(
        data_dir,
        "bioware.xml",
        "bioware",
        "bioware",
        lambda el, e: e.__setitem__("essenceText", text(el, "ess") or None),
    )

    def quality_enrich(el, e):
        k = text(el, "karma")
        try:
            e["karma"] = int(k) if k else None
        except ValueError:
            e["karma"] = None

    all_entries += entries_from(data_dir, "qualities.xml", "quality", "quality", quality_enrich)

    # Adept powers (modifiers for Improved Reflexes, etc.)
    def power_enrich(el, e):
        # Power point cost is often a formula; store raw text in notes when useful.
        pts = text(el, "points")
        if pts:
            e["notes"] = f"PP {pts}"
        e["category"] = text(el, "action") or "Adept Power"

    all_entries += entries_from(data_dir, "powers.xml", "power", "adeptPower", power_enrich)

    # Skills
    spath = data_dir / "skills.xml"
    if spath.exists():
        root = ET.parse(spath).getroot()
        skill_count = 0
        for el in root.findall(".//skill"):
            name = text(el, "name")
            if not name:
                continue
            cat = text(el, "category")
            lower = cat.lower()
            is_knowledge = (
                "knowledge" in lower
                or lower in ("academic", "interest", "language", "professional", "street")
            )
            notes = "knowledge" if is_knowledge else "active"
            if "language" in lower:
                kind_cat = "Language"
                notes = "language"
            elif is_knowledge:
                kind_cat = cat or "Knowledge"
            else:
                kind_cat = cat or "Active"
            all_entries.append(
                {
                    "id": text(el, "id") or f"skill:{name}",
                    "kind": "skill",
                    "name": name,
                    "category": kind_cat,
                    "costText": "",
                    "costNuyen": None,
                    "availability": text(el, "attribute"),
                    "source": text(el, "source"),
                    "page": text(el, "page"),
                    "essenceText": None,
                    "karma": None,
                    "damage": None,
                    "armorRating": None,
                    "notes": notes,
                    "modifiers": [],
                }
            )
            skill_count += 1
        print(f"skills.xml skill {skill_count}")

    cpath = data_dir / "contacts.xml"
    if cpath.exists():
        root = ET.parse(cpath).getroot()
        for el in root.findall(".//contact"):
            name = (el.text or "").strip()
            if not name:
                continue
            all_entries.append(
                {
                    "id": f"contactrole:{name}",
                    "kind": "contactRole",
                    "name": name,
                    "category": "Role",
                    "costText": "",
                    "costNuyen": None,
                    "availability": "",
                    "source": "",
                    "page": "",
                    "essenceText": None,
                    "karma": None,
                    "damage": None,
                    "armorRating": None,
                    "notes": "",
                    "modifiers": [],
                }
            )

    seen: set[str] = set()
    unique: list[dict] = []
    for e in all_entries:
        if e["id"] in seen:
            continue
        seen.add(e["id"])
        unique.append(e)
    unique.sort(key=lambda e: (e["kind"], e["name"].lower()))

    kinds: dict[str, int] = {}
    mod_count = 0
    for e in unique:
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
        if e.get("modifiers"):
            mod_count += 1

    payload = {
        "manifest": {
            "formatVersion": 2,
            "source": "Derived from Chummer5a data XML (GPL-3.0). See Catalog/NOTICE.txt.",
            "entryCount": len(unique),
            "kinds": kinds,
            "entriesWithModifiers": mod_count,
        },
        "entries": unique,
    }
    out_path = out_dir / "sr5_catalog.json"
    out_path.write_text(json.dumps(payload, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"wrote {out_path} ({out_path.stat().st_size} bytes, {len(unique)} entries)")
    print("kinds", kinds)
    print("entries with modifiers", mod_count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
