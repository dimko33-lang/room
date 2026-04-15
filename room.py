#!/usr/bin/env python3
"""
room — пустота
Ни ролей. Ни инструкций. Только диалог.
"""

import json
import os
import re
import secrets
import subprocess
import time
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv
from flask import Flask, Response, jsonify, request, stream_with_context

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
        with open(MEMORY_FILE, 'r', encoding='utf-8') as f:
            memory.extend(json.load(f))
    except:
        pass

def save_memory():
    with open(MEMORY_FILE, 'w', encoding='utf-8') as f:
        json.dump(memory, f, ensure_ascii=False, indent=2)

def get_or_create_alias():
    if ALIAS_FILE.exists():
        return ALIAS_FILE.read_text().strip()
    alias_code = secrets.token_hex(6)
    alias = f"-empty-web-{alias_code}"
    ALIAS_FILE.write_text(alias)
    return alias

ROOM_ALIAS = get_or_create_alias()

def log_to_file(role, content):
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        f.write(f"[{timestamp}] {role}: {content}\n---\n")

app = Flask(__name__)

HTML = """
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
<title>room</title>

<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:ital,wght@0,400;0,500;0,600;1,400;1,500;1,600&display=swap');

* {
    box-sizing: border-box;
}

html, body {
    margin: 0;
    padding: 0;
    height: 100dvh;
}

body {
    background: #000000;
    color: #fff;
    font-family: 'Inter', system-ui, sans-serif;
    font-style: italic;
    font-weight: 400;
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
}

::selection {
    background: rgba(255, 255, 255, 0.1);
    color: inherit;
}
::-moz-selection {
    background: rgba(255, 255, 255, 0.1);
    color: inherit;
}

#chatMessages {
    position: fixed;
    top: 10px;
    left: 10px;
    right: 10px;
    bottom: 50px;
    overflow-y: auto;
    padding: 10px;
    z-index: 2;
}

.msgWrap {
    margin-bottom: 4px;
    position: relative;
    cursor: default;
    user-select: text;
    -webkit-user-select: text;
}

.msg {
    margin: 0;
    letter-spacing: 0.02em;
    line-height: 1.45;
    word-break: break-word;
    white-space: pre-wrap;
    font-size: 14px;
    font-family: 'Inter', system-ui, sans-serif;
    font-style: italic;
    user-select: text;
    -webkit-user-select: text;
}

.msg.assistant {
    opacity: 1;
    color: #dceee1;
}

.msg.user {
    opacity: 0.45;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.82);
}

#messageInput {
    position: fixed;
    bottom: 12px;
    left: 16px;
    right: 16px;
    width: auto;
    background: transparent;
    color: #fff;
    border: none;
    outline: none;
    font-family: 'Inter', system-ui, sans-serif;
    font-size: 14px;
    font-style: italic;
    padding: 0;
    caret-color: rgba(255, 255, 255, 0.4);
}

#messageInput::placeholder {
    content: "";
    opacity: 0;
}

::-webkit-scrollbar {
    width: 8px;
}

::-webkit-scrollbar-track {
    background: #000;
}

::-webkit-scrollbar-thumb {
    background: #2a2a2a;
    border-radius: 4px;
}

* {
    scrollbar-width: thin;
    scrollbar-color: #2a2a2a #000;
}

@media (max-width: 720px) {
    .msg {
        font-size: 13px;
    }
    .msg.user {
        font-size: 11px;
    }
}
</style>
<link rel="stylesheet" href="/css" id="dynamic-css">
</head>
<body>

<div id="chatMessages"></div>
<input type="text" id="messageInput" autofocus autocomplete="off">

<script>
const chatDiv = document.getElementById('chatMessages');
const input = document.getElementById('messageInput');

let isSending = false;
let currentAssistantMsg = null;

function refreshCSS() {
    const link = document.getElementById('dynamic-css');
    link.href = '/css?' + Date.now();
}

async function loadMemory() {
    try {
        const res = await fetch('/memory');
        const data = await res.json();
        const wasAtBottom = chatDiv.scrollHeight - chatDiv.scrollTop - chatDiv.clientHeight < 10;
        
        chatDiv.innerHTML = '';
        data.forEach((msg, idx) => {
            addMessageToUI(msg.role, msg.content, idx);
        });
        
        if (wasAtBottom) {
            chatDiv.scrollTop = chatDiv.scrollHeight;
        }
    } catch (e) {
        console.error('Failed to load memory:', e);
    }
}

function addMessageToUI(role, content, idx) {
    const wrap = document.createElement('div');
    wrap.className = 'msgWrap';
    wrap.dataset.index = idx;
    wrap.style.userSelect = 'text';
    wrap.style.webkitUserSelect = 'text';
    
    let lastClick = 0;
    wrap.onclick = (e) => {
        const now = Date.now();
        if (now - lastClick < 300) {
            e.stopPropagation();
            fetch('/delete', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({index: parseInt(wrap.dataset.index)})
            }).then(res => res.ok && loadMemory());
        }
        lastClick = now;
    };
    
    const msgDiv = document.createElement('div');
    msgDiv.className = `msg ${role}`;
    msgDiv.textContent = content;
    msgDiv.style.userSelect = 'text';
    msgDiv.style.webkitUserSelect = 'text';
    
    wrap.appendChild(msgDiv);
    chatDiv.appendChild(wrap);
}

function updateLastMessage(content) {
    if (currentAssistantMsg) {
        currentAssistantMsg.querySelector('.msg').textContent = content;
    }
}

async function sendMessage() {
    const text = input.value.trim();
    if (!text || isSending) return;
    
    isSending = true;
    input.value = '';
    input.disabled = true;
    
    addMessageToUI('user', text, -1);
    
    const wrap = document.createElement('div');
    wrap.className = 'msgWrap';
    wrap.style.userSelect = 'text';
    wrap.style.webkitUserSelect = 'text';
    const msgDiv = document.createElement('div');
    msgDiv.className = 'msg assistant';
    msgDiv.textContent = '';
    msgDiv.style.userSelect = 'text';
    msgDiv.style.webkitUserSelect = 'text';
    wrap.appendChild(msgDiv);
    chatDiv.appendChild(wrap);
    currentAssistantMsg = wrap;
    
    chatDiv.scrollTop = chatDiv.scrollHeight;
    
    try {
        const res = await fetch('/chat', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({message: text})
        });
        
        if (!res.ok) throw new Error('Chat failed');
        
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let fullResponse = '';
        
        while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            
            const chunk = decoder.decode(value, {stream: true});
            fullResponse += chunk;
            updateLastMessage(fullResponse);
            chatDiv.scrollTop = chatDiv.scrollHeight;
        }
        
        await loadMemory();
        refreshCSS();
        
    } catch (e) {
        console.error(e);
    } finally {
        isSending = false;
        input.disabled = false;
        input.focus();
        currentAssistantMsg = null;
    }
}

input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

loadMemory();
input.focus();
</script>
</body>
</html>
"""

def parse_and_execute_tools(content: str):
    changed = False
    
    cmd_pattern = r'\[CMD\](.*?)\[/CMD\]'
    for match in re.finditer(cmd_pattern, content, re.DOTALL):
        cmd = match.group(1).strip()
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=ROOMS_DIR
            )
            output = result.stdout + result.stderr
            if not output:
                output = "(нет вывода)"
            content = content.replace(match.group(0), f"[выполнено: {cmd}]\n{output}")
        except Exception as e:
            content = content.replace(match.group(0), f"[ошибка: {cmd}]\n{str(e)}")
    
    css_pattern = r'\[CSS\](.*?)\[/CSS\]'
    for match in re.finditer(css_pattern, content, re.DOTALL):
        css = match.group(1).strip()
        try:
            CSS_FILE.write_text(css, encoding='utf-8')
            content = content.replace(match.group(0), f"[стиль применён]")
            changed = True
        except Exception as e:
            content = content.replace(match.group(0), f"[ошибка CSS: {str(e)}]")
    
    return content, changed

@app.route('/')
def index():
    parsed = urlparse(request.url)
    raw_query = parsed.query
    if not raw_query:
        return '', 404
    if raw_query != ROOM_ALIAS:
        return '', 404
    return HTML

@app.route('/css')
def get_css():
    if CSS_FILE.exists():
        return Response(CSS_FILE.read_text(), mimetype='text/css')
    return '', 200

@app.route('/memory')
def get_memory():
    return jsonify(memory)

@app.route('/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_msg = data.get('message', '').strip()
    
    if not user_msg:
        return jsonify({'error': 'empty'}), 400
    
    memory.append({"role": "user", "content": user_msg})
    save_memory()
    log_to_file('user', user_msg)
    
    def generate():
        full_response = ""
        css_changed = False
        try:
            provider = os.getenv('DEFAULT_PROVIDER', 'groq')
            model = os.getenv('DEFAULT_MODEL', 'moonshotai/kimi-k2-instruct-0905')
            
            for chunk in agent.chat_stream(memory, provider=provider, model=model):
                try:
                    clean_chunk = chunk.encode('latin-1').decode('utf-8')
                except:
                    clean_chunk = chunk
                full_response += clean_chunk
                yield clean_chunk
            
            if '[CMD]' in full_response or '[CSS]' in full_response:
                full_response, css_changed = parse_and_execute_tools(full_response)
            
            memory.append({"role": "assistant", "content": full_response})
            save_memory()
            log_to_file('assistant', full_response)
            
            if css_changed:
                yield "\n\n✨ комната обновилась"
            
        except Exception as e:
            error_msg = f"[ошибка]: {str(e)}"
            memory.append({"role": "assistant", "content": error_msg})
            save_memory()
            log_to_file('assistant', error_msg)
            yield error_msg
    
    return Response(
        stream_with_context(generate()),
        mimetype='text/plain; charset=utf-8',
        headers={'Content-Type': 'text/plain; charset=utf-8'}
    )

@app.route('/delete', methods=['POST'])
def delete_message():
    data = request.get_json()
    idx = data.get('index')
    
    try:
        idx = int(idx)
        if 0 <= idx < len(memory):
            deleted = memory.pop(idx)
            save_memory()
            log_to_file('system', f"удалено [{idx}]: {deleted.get('content', '')[:50]}...")
            return jsonify({'ok': True})
    except (ValueError, TypeError):
        pass
    
    return jsonify({'error': 'bad index'}), 400

if __name__ == '__main__':
    host = os.getenv('HOST', '127.0.0.1')
    port = int(os.getenv('PORT', 8000))
    
    print(f"""
╔══════════════════════════════════════════════════════════╗
║                         ROOM                             ║
╠══════════════════════════════════════════════════════════╣
║  Лог:         {LOG_FILE}
║  Творчество:  {ROOMS_DIR}
╚══════════════════════════════════════════════════════════╝
    """)
    
    app.run(host=host, port=port, debug=False, threaded=True)
