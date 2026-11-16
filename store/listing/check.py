#!/usr/bin/env python3
"""Checks the store texts in this folder against Apple's limits (name 30, subtitle 30,
keywords 100, promotional text 170, description 4000) and that the keyword field
repeats no word of the name or subtitle (Apple already indexes those).
Run: python3 -I store/listing/check.py"""
import glob, os, re, sys

LIMITS = {"Name": 30, "Subtitle": 30, "Keywords": 100, "Promotional text": 170, "Description": 4000}
bad = 0
for path in sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "*.md"))):
    if os.path.basename(path) == "README.md":
        continue
    text = open(path, encoding="utf-8").read()
    fields = dict(re.findall(r"^## (.+?)\n\n(.*?)(?=\n## |\Z)", text, flags=re.S | re.M))
    fields = {k.strip(): v.strip() for k, v in fields.items()}
    report = []
    for field, limit in LIMITS.items():
        value = fields.get(field)
        if value is None:
            report.append(f"{field}: missing"); bad += 1; continue
        n = len(value)
        if n > limit:
            report.append(f"{field}: {n} > {limit}"); bad += 1
        else:
            report.append(f"{field} {n}/{limit}")
    kw = fields.get("Keywords", "")
    if " ," in kw or ", " in kw:
        report.append("keywords: no spaces around commas"); bad += 1
    shown = set(re.findall(r"\w+", (fields.get("Name", "") + " " + fields.get("Subtitle", "")).lower()))
    repeats = sorted({w for k in kw.lower().split(",") for w in re.findall(r"\w+", k) if w in shown})
    if repeats:
        report.append(f"keywords repeat name/subtitle words: {', '.join(repeats)}"); bad += 1
    print(os.path.basename(path).ljust(12), " · ".join(report))
sys.exit(1 if bad else 0)
