"""
empty room agent — чистый коннектор к LLM
Никаких сессий, базы данных, глобальных патчей.
"""

import json
import os
import re
import shlex
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Generator

import requests
from dotenv import load_dotenv

load_dotenv()


class EmptyAgent:
    """Минимальный агент для Пустой Комнаты."""
    
    GROQ_LABELS = {
        "llama-3.1-8b-instant": "Llama 3.1 8B",
        "llama-3.3-70b-versatile": "Llama 3.3 70B",
        "qwen-qwq-32b": "Qwen QWQ 32B",
    }
    
    def __init__(self, rooms_dir: Optional[Path] = None):
        self.groq_key = os.getenv("GROQ_API_KEY", "").strip()
        self.openrouter_key = os.getenv("OPENROUTER_API_KEY", "").strip()
        self.kimi_key = os.getenv("KIMI_API_KEY", "").strip()
        
        self.default_provider = os.getenv("DEFAULT_PROVIDER", "groq").strip()
        self.default_model = os.getenv("DEFAULT_MODEL", "llama-3.3-70b-versatile").strip()
        
        self.timeout = 120
        self.rooms_dir = rooms_dir or Path(__file__).parent / "rooms"
        self.rooms_dir.mkdir(exist_ok=True)
    
    def label_for(self, provider: str, model: str) -> str:
        provider = provider.lower()
        if provider == "groq":
            return self.GROQ_LABELS.get(model, model)
        return model
    
    def _call_llm(self, provider: str, model: str, messages: List[Dict]) -> str:
        provider = provider.lower()
        
        if provider == "groq":
            url = "https://api.groq.com/openai/v1/chat/completions"
            headers = {"Authorization": f"Bearer {self.groq_key}", "Content-Type": "application/json"}
            payload = {"model": model, "messages": messages, "temperature": 0.9}
        elif provider == "kimi":
            url = "https://api.moonshot.ai/v1/chat/completions"
            headers = {"Authorization": f"Bearer {self.kimi_key}", "Content-Type": "application/json"}
            payload = {"model": model, "messages": messages}
        elif provider == "openrouter":
            url = "https://openrouter.ai/api/v1/chat/completions"
            headers = {
                "Authorization": f"Bearer {self.openrouter_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": os.getenv("PUBLIC_URL", "http://localhost"),
            }
            payload = {"model": model, "messages": messages, "temperature": 0.9}
        else:
            raise ValueError(f"Unknown provider: {provider}")
        
        resp = requests.post(url, headers=headers, json=payload, timeout=self.timeout)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"] or ""
    
    def _call_llm_stream(self, provider: str, model: str, messages: List[Dict]) -> Generator[str, None, None]:
        """Потоковый вызов LLM."""
        provider = provider.lower()
        
        if provider == "groq":
            url = "https://api.groq.com/openai/v1/chat/completions"
            headers = {"Authorization": f"Bearer {self.groq_key}", "Content-Type": "application/json"}
            payload = {"model": model, "messages": messages, "temperature": 0.9, "stream": True}
        elif provider == "kimi":
            url = "https://api.moonshot.ai/v1/chat/completions"
            headers = {"Authorization": f"Bearer {self.kimi_key}", "Content-Type": "application/json"}
            payload = {"model": model, "messages": messages, "stream": True}
        elif provider == "openrouter":
            url = "https://openrouter.ai/api/v1/chat/completions"
            headers = {
                "Authorization": f"Bearer {self.openrouter_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": os.getenv("PUBLIC_URL", "http://localhost"),
            }
            payload = {"model": model, "messages": messages, "temperature": 0.9, "stream": True}
        else:
            raise ValueError(f"Unknown provider: {provider}")
        
        resp = requests.post(url, headers=headers, json=payload, timeout=self.timeout, stream=True)
        resp.raise_for_status()
        
        for line in resp.iter_lines(decode_unicode=True):
            if line and line.startswith("data: "):
                data = line[6:]
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        yield content
                except json.JSONDecodeError:
                    continue
    
    def execute_command(self, command: str) -> Dict:
        """Выполнить shell-команду внутри rooms/."""
        try:
            result = subprocess.run(
                shlex.split(command),
                capture_output=True,
                text=True,
                timeout=30,
                cwd=self.rooms_dir
            )
            output = result.stdout + result.stderr
            return {
                "success": True,
                "output": output or "(нет вывода)",
                "exit_code": result.returncode
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "output": "Таймаут 30с", "exit_code": -1}
        except Exception as e:
            return {"success": False, "output": str(e), "exit_code": -1}
    
    def parse_and_execute(self, text: str) -> str:
        """
        Находит [CMD] и [CSS] в тексте, выполняет их, возвращает обработанный текст.
        """
        # [CMD]
        cmd_pattern = r'\[CMD\](.*?)\[/CMD\]'
        for match in re.finditer(cmd_pattern, text, re.DOTALL):
            cmd = match.group(1).strip()
            result = self.execute_command(cmd)
            replacement = f"[выполнено: {cmd}]\n{result['output']}"
            text = text.replace(match.group(0), replacement)
        
        # [CSS] — просто возвращаем css отдельно, обработка в room.py
        # Здесь можно оставить как есть или вырезать
        
        return text
    
    def extract_css(self, text: str) -> Optional[str]:
        """Извлечь CSS из [CSS]...[/CSS]."""
        match = re.search(r'\[CSS\](.*?)\[/CSS\]', text, re.DOTALL)
        if match:
            return match.group(1).strip()
        return None
    
    def chat(self, messages: List[Dict], provider: Optional[str] = None, model: Optional[str] = None) -> str:
        """Синхронный вызов (без потока)."""
        provider = (provider or self.default_provider).strip()
        model = (model or self.default_model).strip()
        return self._call_llm(provider, model, messages)
    
    def chat_stream(self, messages: List[Dict], provider: Optional[str] = None, model: Optional[str] = None) -> Generator[str, None, None]:
        """Потоковый вызов — для room.py."""
        provider = (provider or self.default_provider).strip()
        model = (model or self.default_model).strip()
        yield from self._call_llm_stream(provider, model, messages)


# Экземпляр для импорта
agent = EmptyAgent()
