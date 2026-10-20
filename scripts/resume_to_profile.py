#!/usr/bin/env python3
"""Turns resume text into a short, anonymized tech profile for DevBoard's resume-based questions.

1. Contact details (emails, phone numbers, URLs) are scrubbed locally before anything leaves your Mac.
2. Gemini rewrites the rest into a profile with no names, employers, schools or locations.
3. The profile is printed to stdout so setup.sh can show it to you before saving.

Usage: python3 scripts/resume_to_profile.py <resume.txt>   (setup.sh extracts text from PDF/DOCX first)
Needs ~/.config/devboard/gemini_key. Standard library only.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

KEY_FILE = os.path.expanduser("~/.config/devboard/gemini_key")
MODELS = [("gemini-2.5-flash", {"thinkingBudget": 0}), ("gemini-3.5-flash", {"thinkingLevel": "low"}), ("gemini-flash-latest", {})]

INSTRUCTIONS = """You convert a resume into a short technical profile used to generate interview questions.
Strict privacy rules:
- Never include the person's name, email, phone, address, city, links, usernames or school/university names.
- Replace employer names with a neutral description, e.g. "a large fintech company" or "a cloud security startup".
- Keep product/feature names only if they are generic industry terms (e.g. "UPI payments", "search ranking").
Content rules:
- Plain text, under 300 words. Start with one line: role and years of experience.
- For each job: one line describing the company type and role, then 2-5 bullet points of what they built, \
including tech, scale numbers and notable design choices (these make the best interview questions).
- Then side projects, then a one-line skills list.
- Do not invent anything that is not in the resume."""


def scrub(text: str) -> str:
    text = re.sub(r"[\w.+-]+@[\w-]+\.[\w.-]+", "[email]", text)
    text = re.sub(r"https?://\S+|www\.\S+|\b(?:linkedin|github)\.com/\S+", "[link]", text, flags=re.I)
    # Phone numbers: digit runs with separators and at least 10 digits (so "2020 - 2024" survives).
    text = re.sub(r"\+?\d[\d\s().-]{8,}\d",
                  lambda m: "[phone]" if sum(c.isdigit() for c in m.group()) >= 10 else m.group(), text)
    # LaTeX resumes: drop commands but keep their text arguments.
    text = re.sub(r"\\[a-zA-Z]+\*?(\[[^\]]*\])?", " ", text)
    text = re.sub(r"[{}]", " ", text)
    return re.sub(r"[ \t]+", " ", text).strip()


def call(model: str, thinking: dict, key: str, resume: str) -> str:
    config = {"temperature": 0.2}
    if thinking:
        config["thinkingConfig"] = thinking
    body = {
        "systemInstruction": {"parts": [{"text": INSTRUCTIONS}]},
        "contents": [{"role": "user", "parts": [{"text": "Resume:\n" + resume}]}],
        "generationConfig": config,
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.load(resp)
    parts = data["candidates"][0]["content"]["parts"]
    return "".join(p.get("text", "") for p in parts if not p.get("thought")).strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        key = open(KEY_FILE).read().strip()
    except OSError:
        print("No Gemini key found. Run ./setup.sh and add one first.", file=sys.stderr)
        return 1
    resume = scrub(open(sys.argv[1], encoding="utf-8", errors="ignore").read())
    if len(resume) < 200:
        print("That resume has very little text. Is it a scanned image?", file=sys.stderr)
        return 1
    last = None
    for model, thinking in MODELS:
        try:
            profile = call(model, thinking, key, resume[:20000])
            if profile:
                print(scrub(profile))
                return 0
        except (urllib.error.URLError, KeyError, IndexError, TimeoutError) as e:
            last = e  # overloaded or unavailable: try the next model
    print(f"Gemini could not create a profile right now ({last}). Try again in a minute.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
