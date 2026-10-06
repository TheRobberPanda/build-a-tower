#!/usr/bin/env python3
"""Generate an image via OpenRouter. Usage: gen_image.py OUT.png "prompt" [model] [reference.png]
Prints the charge so it can be logged in BUDGET.md. Reads OPENROUTER_API_KEY from .env."""
import base64, json, os, sys, urllib.request

def key():
    for line in open(os.path.join(os.path.dirname(__file__), "..", ".env")):
        if line.startswith("OPENROUTER_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"')
    sys.exit("no OPENROUTER_API_KEY")

out, prompt = sys.argv[1], sys.argv[2]
model = sys.argv[3] if len(sys.argv) > 3 else "google/gemini-3.1-flash-image"
content = [{"type": "text", "text": prompt}]
if len(sys.argv) > 4:  # style reference image
    ref = base64.b64encode(open(sys.argv[4], "rb").read()).decode()
    content.append({"type": "image_url", "image_url": {"url": "data:image/png;base64," + ref}})
body = {"model": model, "modalities": ["image", "text"], "usage": {"include": True},
        "messages": [{"role": "user", "content": content}]}
req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", json.dumps(body).encode(),
                             {"Authorization": "Bearer " + key(), "Content-Type": "application/json"})
resp = json.load(urllib.request.urlopen(req, timeout=180))
msg = resp["choices"][0]["message"]
url = msg["images"][0]["image_url"]["url"]
open(out, "wb").write(base64.b64decode(url.split(",", 1)[1]))
print("saved", out, "cost", resp.get("usage", {}).get("cost"))
