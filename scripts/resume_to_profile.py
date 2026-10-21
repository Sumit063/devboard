#!/usr/bin/env python3
"""Turns resume text into a short, anonymized tech profile for DevBoard's resume-based questions.

1. Contact details (emails, phone numbers, URLs) are scrubbed locally before anything leaves your Mac.
2. The configured AI provider (Gemini, Claude or an OpenAI-compatible API) rewrites the rest into a profile
   with no names, employers, schools or locations.
3. The profile is printed to stdout so setup.sh can show it to you before saving.

Usage: python3 scripts/resume_to_profile.py <resume.txt>   (setup.sh extracts text from PDF/DOCX first)
Needs ~/.config/devboard/api_key (and ai_provider/ai_model/ai_base_url in config.json). Standard library only.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

CONFIG_DIR = os.path.expanduser("~/.config/devboard")
GEMINI_MODELS = [("gemini-3.8-flash", {"thinkingLevel": "low"}), ("gemini-3.5-flash", {"thinkingLevel": "low"}), ("gemini-flash-latest", {})]

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


def post(url: str, headers: dict, body: dict) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.load(resp)


def call_claude(model: str, key: str, resume: str) -> str:
    data = post("https://api.anthropic.com/v1/messages", {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "server-side-fallback-2026-07-01",
    }, {
        "model": model,
        "max_tokens": 16000,
        "system": INSTRUCTIONS,
        "messages": [{"role": "user", "content": "Resume:\n" + resume}],
        "output_config": {"effort": "low"},
        "fallbacks": "default",  # re-run on Anthropic's recommended model if a safety classifier declines
    })
    if data.get("stop_reason") == "refusal":
        raise KeyError("Claude declined the request")
    return "".join(b["text"] for b in data["content"] if b.get("type") == "text").strip()


def call_openai(model: str, key: str, base_url: str, resume: str) -> str:
    data = post(base_url.rstrip("/") + "/chat/completions", {"Authorization": f"Bearer {key}"}, {
        "model": model,
        "messages": [{"role": "system", "content": INSTRUCTIONS}, {"role": "user", "content": "Resume:\n" + resume}],
    })
    return data["choices"][0]["message"]["content"].strip()


def call_gemini(model: str, thinking: dict, key: str, resume: str) -> str:
    config = {"temperature": 0.2}
    if thinking:
        config["thinkingConfig"] = thinking
    body = {
        "systemInstruction": {"parts": [{"text": INSTRUCTIONS}]},
        "contents": [{"role": "user", "parts": [{"text": "Resume:\n" + resume}]}],
        "generationConfig": config,
    }
    data = post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                {"x-goog-api-key": key}, body)
    parts = data["candidates"][0]["content"]["parts"]
    return "".join(p.get("text", "") for p in parts if not p.get("thought")).strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    key = ""
    for name in ("api_key", "gemini_key"):  # gemini_key: setups from before api_key
        try:
            key = open(os.path.join(CONFIG_DIR, name)).read().strip()
            break
        except OSError:
            pass
    if not key:
        print("No API key found. Run ./setup.sh and add one first.", file=sys.stderr)
        return 1
    try:
        cfg = json.load(open(os.path.join(CONFIG_DIR, "config.json")))
    except (OSError, ValueError):
        cfg = {}
    provider = (cfg.get("ai_provider") or "gemini").strip().lower()
    model = (cfg.get("ai_model") or "").strip()
    resume = scrub(open(sys.argv[1], encoding="utf-8", errors="ignore").read())
    if len(resume) < 200:
        print("That resume has very little text. Is it a scanned image?", file=sys.stderr)
        return 1
    resume = resume[:20000]
    if provider in ("claude", "anthropic"):
        attempts = [lambda: call_claude(model or "claude-opus-5-5", key, resume)]
    elif provider == "openai":
        if not model:
            print("Set ai_model in ~/.config/devboard/config.json for ai_provider openai.", file=sys.stderr)
            return 1
        base = (cfg.get("ai_base_url") or "").strip() or "https://api.openai.com/v1"
        attempts = [lambda: call_openai(model, key, base, resume)]
    else:
        models = [(model, {})] if model else GEMINI_MODELS
        attempts = [lambda m=m, t=t: call_gemini(m, t, key, resume) for m, t in models]
    last = None
    for attempt in attempts:
        try:
            profile = attempt()
            if profile:
                print(scrub(profile))
                return 0
        except (urllib.error.URLError, KeyError, IndexError, TimeoutError) as e:
            last = e  # overloaded or unavailable: try the next model
    print(f"The AI provider could not create a profile right now ({last}). Try again in a minute.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
