#!/usr/bin/env python3
"""Ask DeepSeek (OpenRouter, :nitro routing) a question. Usage: tools/ask.py "prompt" [files...]
Prints the answer and the cost (logged to stderr). Key from .env, never printed."""
import json, os, sys, urllib.request

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
key = next(l.split("=", 1)[1].strip() for l in open(os.path.join(root, ".env")) if l.startswith("OPENROUTER_API_KEY="))
prompt = sys.argv[1] + "".join(f"\n\n=== {f} ===\n" + open(f).read() for f in sys.argv[2:])
body = {"model": os.environ.get("MODEL", "deepseek/deepseek-v4-pro:nitro"), "messages": [{"role": "user", "content": prompt}], "usage": {"include": True}}
req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", json.dumps(body).encode(),
                             {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
r = json.load(urllib.request.urlopen(req, timeout=600))
print(r["choices"][0]["message"]["content"])
print(f"[cost ${r.get('usage', {}).get('cost', 0):.4f}]", file=sys.stderr)
