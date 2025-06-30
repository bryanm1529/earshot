#!/usr/bin/env python3
"""
Sprint 6: The Cognitive Engine
Main orchestrator for real-time conversational assistance on HUD
"""

import asyncio
import aiohttp
import json
import re
import time
import logging
from collections import deque
from dataclasses import dataclass
from typing import Optional, Dict, Any
import argparse
import websockets
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('cognitive_engine')

@dataclass
class CognitiveConfig:
    """Configuration for the Cognitive Engine"""
    whisper_host: str = "127.0.0.1"
    whisper_port: int = 9080
    ollama_host: str = "127.0.0.1"
    ollama_port: int = 11434
    hud_websocket: str = "ws://localhost:8080"

    # Chronicler settings
    context_max_length: int = 50
    summarization_timer: float = 5.0
    summarization_model: str = "phi3:mini"

    # Advisor settings
    advisor_model: str = "llama3:8b"
    question_patterns: list = None
    advisor_timeout: float = 0.7  # 700ms max response time
    max_context_tokens: int = 300  # Sprint 7: Prevent LLM stalls

    def __post_init__(self):
        # Environment variable overrides
        self.advisor_model = os.getenv('COPILOT_ADVISOR_MODEL', self.advisor_model)
        self.chronicler_enabled = os.getenv('COPILOT_CHRONICLER_ENABLED', 'true').lower() == 'true'

        if self.question_patterns is None:
            # Sprint 6: Fast regex patterns for question detection
            self.question_patterns = [
                r'\?$',                    # Ends with question mark
                r'^(what|how|why|when|where|who)\s',  # Question words
                r'^(is|are|can|could|should|would)\s', # Auxiliary verbs
                r'^(do|does|did)\s',       # Do-questions
                r'^(tell me|explain)',     # Direct requests
            ]

        # Log effective configuration on startup
        logger.info(f"🔧 Config: Advisor model={self.advisor_model}, Chronicler={'ENABLED' if self.chronicler_enabled else 'DISABLED'}")

class Chronicler:
    """
    Conversational Memory System
    Subscribes to /inference cold path for high-accuracy context
    """

    def __init__(self, config: CognitiveConfig):
        self.config = config
        self.context_store = deque(maxlen=config.context_max_length)
        self.current_summary = ""
        self.entities = {}
        self.last_summarization = time.time()
        self.pending_text = ""

        logger.info(f"Chronicler initialized with max_length={config.context_max_length}")

    def add_transcription(self, text: str, timestamp: float = None):
        """Add new transcription to context store"""
        if timestamp is None:
            timestamp = time.time()

        # Add to pending text buffer
        self.pending_text += f" {text}".strip()

        # Check if we have a complete sentence or timer expired
        has_sentence = any(punct in text for punct in '.!?')
        timer_expired = (time.time() - self.last_summarization) > self.config.summarization_timer

        if has_sentence or timer_expired:
            self._trigger_summarization()

    def _trigger_summarization(self):
        """Trigger summarization of pending text"""
        if not self.pending_text.strip():
            return

        # Add to context store
        self.context_store.append({
            'timestamp': time.time(),
            'text': self.pending_text.strip()
        })

        # Reset
        self.pending_text = ""
        self.last_summarization = time.time()

        logger.info(f"Context updated: {len(self.context_store)} items")

    def get_context_dict(self) -> Dict[str, Any]:
        """Get current context for Advisor prompts"""
        return {
            "summary": self.current_summary,
            "entities": self.entities
        }

    def debug_print_context(self):
        """Debug method: print current context state"""
        print(f"\n=== CHRONICLER DEBUG ({time.strftime('%H:%M:%S')}) ===")
        print(f"Context items: {len(self.context_store)}")
        print(f"Current summary: {self.current_summary}")
        print(f"Entities: {list(self.entities.keys())}")
        print("=" * 50)

class Advisor:
    """
    Real-time Assistance Engine
    Triggered by questions from /hot_stream, provides contextual responses
    """

    def __init__(self, config: CognitiveConfig, chronicler: Chronicler):
        self.config = config
        self.chronicler = chronicler
        self.question_regex = re.compile('|'.join(config.question_patterns), re.IGNORECASE)
        self.last_response_time = 0
        self.ollama_url = f"http://{config.ollama_host}:{config.ollama_port}/api/generate"

        logger.info(f"Advisor initialized with model={config.advisor_model}")

    def is_question(self, text: str) -> bool:
        """Fast regex check if text contains a question"""
        return bool(self.question_regex.search(text.strip()))

    async def _call_ollama(self, prompt: str) -> Optional[str]:
        """Make async call to Ollama API with timeout"""
        payload = {
            "model": self.config.advisor_model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "top_k": 20,
                "top_p": 0.9,
                "num_predict": 100  # Limit response length for speed
            }
        }

        try:
            timeout = aiohttp.ClientTimeout(total=self.config.advisor_timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(self.ollama_url, json=payload) as response:
                    if response.status == 200:
                        result = await response.json()
                        return result.get('response', '').strip()
                    else:
                        logger.error(f"Ollama API error: {response.status}")
                        return None
        except asyncio.TimeoutError:
            logger.warning(f"Ollama timeout ({self.config.advisor_timeout}s)")
            return None
        except Exception as e:
            logger.error(f"Ollama error: {e}")
            return None

    def _build_advisor_prompt(self, question: str, context: Dict[str, Any]) -> str:
        """Build prompt for Advisor with context"""
        # Sprint 7: Cap context to prevent LLM stalls
        summary = context.get('summary', '')
        if len(summary) > self.config.max_context_tokens:
            summary = summary[:self.config.max_context_tokens] + "..."

        entities = context.get('entities', {})
        entity_str = ", ".join(entities.keys()) if entities else "none"

        prompt = f"""You are a real-time AI assistant providing brief, bullet-pointed answers for questions during live conversations.

Context Summary: {summary}
Current Entities: {entity_str}

Question: {question}

Provide a concise response in this format:
• Key point 1
• Key point 2
• Key point 3 (if relevant)

Keep each bullet under 10 words. Focus on essential information only."""

        return prompt

    async def process_hot_stream_text(self, text: str) -> Optional[str]:
        """Process incoming hot stream text and generate advice if needed"""
        if not self.is_question(text):
            return None

        start_time = time.time()

        # Get context from Chronicler
        context = self.chronicler.get_context_dict()

        # Build prompt with context
        prompt = self._build_advisor_prompt(text, context)

        # Call Ollama
        response = await self._call_ollama(prompt)

        response_time = time.time() - start_time
        self.last_response_time = response_time

        if response:
            logger.info(f"Advisor response in {response_time:.3f}s: {response}")
            return response
        else:
            logger.warning(f"No response from Advisor for: {text}")
            return None

class CognitiveEngine:
    """
    Main orchestrator for the Cognitive Co-Pilot system
    """

    def __init__(self, config: CognitiveConfig):
        self.config = config
        self.chronicler = Chronicler(config)
        self.advisor = Advisor(config, self.chronicler)
        self.running = False
        self.whisper_ws = None
        self.reconnect_delay = 1.0  # Start with 1 second
        self.max_reconnect_delay = 10.0  # Cap at 10 seconds
        self.stats = {
            "questions_processed": 0,
            "context_updates": 0,
            "average_response_time": 0.0,
            "whisper_reconnects": 0
        }

        logger.info("Cognitive Engine initialized")

    async def start(self):
        """Start the cognitive engine"""
        self.running = True
        logger.info("🧠 Starting Cognitive Engine...")

        # Start background tasks
        tasks = [
            asyncio.create_task(self._chronicler_ticker()),
            asyncio.create_task(self._whisper_websocket_manager()),
            asyncio.create_task(self._stats_reporter())
        ]

        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Shutting down Cognitive Engine...")
            self.running = False
            for task in tasks:
                task.cancel()

    async def _whisper_websocket_manager(self):
        """Manage WebSocket connection to Whisper server with resilience"""
        while self.running:
            try:
                await self._connect_to_whisper()
            except Exception as e:
                logger.error(f"Whisper connection failed: {e}")
                await self._handle_reconnect()

    async def _connect_to_whisper(self):
        """Connect to Whisper WebSocket and handle messages"""
        whisper_url = f"ws://{self.config.whisper_host}:{self.config.whisper_port}/hot_stream"
        logger.info(f"🎤 Connecting to Whisper at {whisper_url}")

        try:
            async with websockets.connect(whisper_url) as websocket:
                self.whisper_ws = websocket
                self.reconnect_delay = 1.0  # Reset delay on successful connection
                logger.info("✅ Connected to Whisper server")

                async for message in websocket:
                    if not self.running:
                        break

                    try:
                        data = json.loads(message)
                        await self._process_whisper_message(data)
                    except json.JSONDecodeError:
                        logger.warning(f"Invalid JSON from Whisper: {message}")
                    except Exception as e:
                        logger.error(f"Error processing Whisper message: {e}")

        except websockets.exceptions.ConnectionClosed:
            logger.warning("Whisper connection closed")
            raise
        except Exception as e:
            logger.error(f"Whisper connection error: {e}")
            raise
        finally:
            self.whisper_ws = None

    async def _handle_reconnect(self):
        """Handle reconnection with exponential backoff"""
        if not self.running:
            return

        self.stats["whisper_reconnects"] += 1
        logger.info(f"🔄 Reconnecting to Whisper in {self.reconnect_delay}s...")
        await asyncio.sleep(self.reconnect_delay)

        # Exponential backoff with cap
        self.reconnect_delay = min(self.reconnect_delay * 2, self.max_reconnect_delay)

    async def _process_whisper_message(self, data: Dict[str, Any]):
        """Process incoming message from Whisper hot stream"""
        text = data.get('text', '').strip()
        if not text:
            return

        logger.info(f"🎤 Hot Stream: {text}")

        # Add to chronicler for context
        if self.config.chronicler_enabled:
            self.chronicler.add_transcription(text)
            self.stats["context_updates"] += 1

        # Process with Advisor if it's a question
        if self.advisor.is_question(text):
            response = await self.advisor.process_hot_stream_text(text)
            if response:
                await self._send_to_hud(response)
                self.stats["questions_processed"] += 1

    async def _send_to_hud(self, text: str):
        """Send text to HUD via Tauri event with timestamp for stale data prevention"""
        try:
            # Sprint 7: Add timestamp for stale data prevention
            payload = {
                "text": text,
                "ts": int(time.time() * 1000)  # Milliseconds timestamp
            }

            # TODO: Implement actual Tauri event emission
            # For now, use subprocess to emit Tauri event
            import subprocess
            event_json = json.dumps(payload)

            # This would be the actual Tauri event emission in production
            logger.info(f"🎯 HUD Event: advisor_keywords -> {payload}")

            # Placeholder for Tauri integration:
            # await tauri.emit("advisor_keywords", payload)

        except Exception as e:
            logger.error(f"HUD send error: {e}")

    async def _chronicler_ticker(self):
        """Context ticker: print current summary every 5 seconds"""
        while self.running:
            await asyncio.sleep(5.0)
            if self.running and self.config.chronicler_enabled:
                self.chronicler.debug_print_context()

    async def _hot_stream_monitor(self):
        """Legacy test method - replaced by _whisper_websocket_manager"""
        # This method is kept for compatibility but not used in production
        pass

    async def _stats_reporter(self):
        """Report system statistics"""
        while self.running:
            await asyncio.sleep(30.0)
            if self.running:
                logger.info(f"📊 Stats: {self.stats['questions_processed']} questions, "
                          f"avg response: {self.advisor.last_response_time:.3f}s, "
                          f"reconnects: {self.stats['whisper_reconnects']}")

async def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="Cognitive Engine for Earshot")
    parser.add_argument("--websocket", default="ws://localhost:8080",
                       help="HUD WebSocket URL")
    parser.add_argument("--whisper-host", default="127.0.0.1",
                       help="Whisper server host")
    parser.add_argument("--whisper-port", type=int, default=9080,
                       help="Whisper server port")
    parser.add_argument("--ollama-host", default="127.0.0.1",
                       help="Ollama server host")
    parser.add_argument("--ollama-port", type=int, default=11434,
                       help="Ollama server port")
    parser.add_argument("--debug", action="store_true",
                       help="Enable debug logging")

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Create configuration
    config = CognitiveConfig(
        whisper_host=args.whisper_host,
        whisper_port=args.whisper_port,
        ollama_host=args.ollama_host,
        ollama_port=args.ollama_port,
        hud_websocket=args.websocket
    )

    # Start cognitive engine
    engine = CognitiveEngine(config)
    await engine.start()

if __name__ == "__main__":
    asyncio.run(main())
