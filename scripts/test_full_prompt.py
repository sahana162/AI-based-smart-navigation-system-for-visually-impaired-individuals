import urllib.request
import urllib.error
import json
import time

key = "YOUR_GEMINI_API_KEY"

tools = [
    {"name": "navigateTo", "description": "Navigates to destination", "parameters": {"type": "OBJECT", "properties": {"destination": {"type": "STRING"}}, "required": ["destination"]}},
    {"name": "detectObstacles", "description": "Detect obstacles in front"},
    {"name": "getCurrentLocation", "description": "Current location"},
    {"name": "triggerEmergencySOS", "description": "Emergency SOS"}
]

system_prompt = "You are Lux, a voice AI for visually impaired pedestrians. Converse naturally and call tools when needed."

models = ["gemini-3.5-flash", "gemini-3.1-flash-lite"]

for m in models:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent?key={key}"
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "tools": [{"functionDeclarations": tools}],
        "contents": [{"role": "user", "parts": [{"text": "Hello Lux, can you check for obstacles in front of me?"}]}]
    }
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            dur = time.time() - t0
            body = json.loads(resp.read().decode())
            candidate = body['candidates'][0]['content']['parts'][0]
            print(f"[SUCCESS] {m} in {dur:.2f}s: {candidate}")
    except urllib.error.HTTPError as e:
        dur = time.time() - t0
        print(f"[FAIL {e.code}] {m} in {dur:.2f}s: {e.read().decode()[:200]}")
    except Exception as e:
        dur = time.time() - t0
        print(f"[ERR] {m} in {dur:.2f}s: {e}")
