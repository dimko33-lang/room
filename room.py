#!/usr/bin/env python3

import json
import os
import re
import secrets
import subprocess
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv
from flask import Flask, Response, request, stream_with_context

from agent import agent

load_dotenv()

BASE_DIR = Path(__file__).parent
ROOMS_DIR = BASE_DIR / "rooms"
CSS_FILE = ROOMS_DIR / "current.css"
ALIAS_FILE = BASE_DIR / "room_alias.txt"
LOG_FILE = BASE_DIR / "room.log"
MEMORY_FILE = BASE_DIR / "memory.json"

ROOMS_DIR.mkdir(exist_ok=True)

memory = []

if MEMORY_FILE.exists():
    try:
        memory = json.loads(MEMORY_FILE.read_text(encoding="utf-8"))
    except:
        pass

def save_memory():
    MEMORY_FILE.write_text(json.dumps(memory, ensure_ascii=False), encoding="utf-8")

def log_to_file(content):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(content + "\n\n---\n\n")

def get_alias():
    if ALIAS_FILE.exists():
        return ALIAS_FILE.read_text().strip()
    alias = "-room-" + secrets.token_hex(6)
    ALIAS_FILE.write_text(alias)
    return alias

ROOM_ALIAS = get_alias()

app = Flask(__name__)

HTML = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>room</title>

<style>
body { background:black; color:white; font-family:monospace; margin:0; padding:10px; }
.msg { white-space:pre-wrap; margin-bottom:6px; }
.user { opacity:0.5; }
</style>

<link rel="stylesheet" href="/css">
</head>

<body>

<div id="chat"></div>
<input id="input" autofocus autocomplete="off">

<script>
const chat = document.getElementById('chat');
const input = document.getElementById('input');

function add(role, text){
    const d = document.createElement('div');
    d.className = 'msg ' + role;
    d.textContent = text;
    chat.appendChild(d);
    chat.scrollTop = chat.scrollHeight;
}

input.addEventListener('keydown', async (e)=>{
    if(e.key !== 'Enter') return;

    const text = input.value.trim();
    if(!text) return;

    input.value = '';
    add('user', text);

    const res = await fetch('/chat', {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify({message:text})
    });

    const reader = res.body.getReader();
    const decoder = new TextDecoder();

    let full = "";
    let last = document.createElement('div');
    last.className = 'msg assistant';
    chat.appendChild(last);

    while(true){
        const {done, value} = await reader.read();
        if(done) break;
        full += decoder.decode(value);
        last.textContent = full;
        chat.scrollTop = chat.scrollHeight;
    }

    location.reload(); // обновляем чтобы применился CSS
});
</script>

</body>
</html>
"""

def run_tools(text):
    changed = False

    for m in re.finditer(r'\[CMD\](.*?)\[/CMD\]', text, re.DOTALL):
        cmd = m.group(1).strip()
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=ROOMS_DIR)
            out = r.stdout + r.stderr or "(no output)"
            text = text.replace(m.group(0), out)
        except Exception as e:
            text = text.replace(m.group(0), str(e))

    for m in re.finditer(r'\[CSS\](.*?)\[/CSS\]', text, re.DOTALL):
        css = m.group(1).strip()
        try:
            CSS_FILE.write_text(css, encoding="utf-8")
            text = text.replace(m.group(0), "")
            changed = True
        except Exception as e:
            text = text.replace(m.group(0), str(e))

    return text, changed

@app.route('/')
def index():
    q = urlparse(request.url).query
    if q != ROOM_ALIAS:
        return '', 404
    return HTML

@app.route('/css')
def css():
    if CSS_FILE.exists():
        return Response(CSS_FILE.read_text(), mimetype='text/css')
    return ''

@app.route('/chat', methods=['POST'])
def chat():
    data = request.get_json()
    msg = data.get('message','').strip()

    if not msg:
        return '', 400

    memory.append({"role":"user","content":msg})
    save_memory()
    log_to_file(msg)

    def stream():
        full = ""
        provider = os.getenv('DEFAULT_PROVIDER','groq')
        model = os.getenv('DEFAULT_MODEL','')

        for chunk in agent.chat_stream(memory, provider=provider, model=model):
            full += chunk
            yield chunk

        full, _ = run_tools(full)

        memory.append({"role":"assistant","content":full})
        save_memory()
        log_to_file(full)

    return Response(stream_with_context(stream()), mimetype='text/plain')

if __name__ == '__main__':
    host = os.getenv('HOST','0.0.0.0')
    port = int(os.getenv('PORT',80))
    app.run(host=host, port=port)
