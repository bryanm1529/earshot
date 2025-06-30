#!/usr/bin/env python3
"""
Sprint 8: Optimized Cognitive Engine
Performance-focused version with connection pooling and faster model defaults
"""

import asyncio
import aiohttp
import json
import re
import time
import logging
from collections import deque
from dataclasses import dataclass
from typing import Optional, Dict, Any, List
import argparse
import websockets
import os
from asyncio import Lock

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('optimized_cognitive_engine')

@dataclass
class OptimizedCognitiveConfig:
    """Optimized configuration for Sprint 8 performance targets"""
    whisper_host: str = "127.0.0.1"
    whisper_port: int = 8178
    ollama_host: str = "127.0.0.1"
    ollama_port: int = 11434
    hud_websocket: str = "ws://localhost:8080"

    # Sprint 8: Optimized for speed
    context_max_length: int = 30  # Reduced for faster processing
    summarization_timer: float = 3.0  # Faster summarization
    summarization_model: str = "phi3:mini"  # Faster model

    # Sprint 8: Speed-optimized advisor
    advisor_model: str = "phi3:mini"  # Default to faster model
    question_patterns: list = None
    advisor_timeout: float = 1.5  # Longer timeout for stability
    max_context_tokens: int = 200  # Reduced for speed

    # Sprint 8: Connection pooling
    max_concurrent_requests: int = 3
    connection_pool_size: int = 5
    retry_attempts: int = 2

    def __post_init__(self):
        # Environment variable overrides
        self.advisor_model = os.getenv('COPILOT_ADVISOR_MODEL', self.advisor_model)
        self.chronicler_enabled = os.getenv('COPILOT_CHRONICLER_ENABLED', 'true').lower() == 'true'

        if self.question_patterns is None:
            # Sprint 8: Optimized regex patterns (fewer, faster)
            self.question_patterns = [
                r'\?$',                    # Ends with question mark
                r'^(what|how|why)\s',      # Core question words only
                r'^(is|are|can)\s',        # Common auxiliary verbs
            ]

        # Log effective configuration on startup
        logger.info(f"🚀 Sprint 8 Config: Advisor={self.advisor_model}, Pooling={self.connection_pool_size}, Timeout={self.advisor_timeout}s")

class OptimizedAdvisor:
    """
    Sprint 8: Performance-optimized Advisor with connection pooling
    """

    def __init__(self, config: OptimizedCognitiveConfig, chronicler):
        self.config = config
        self.chronicler = chronicler
        self.question_regex = re.compile('|'.join(config.question_patterns), re.IGNORECASE)
        self.last_response_time = 0
        self.ollama_url = f"http://{config.ollama_host}:{config.ollama_port}/api/generate"

                # Fix 1: Shared TCPConnector (create once, reuse)
        self.shared_connector = aiohttp.TCPConnector(
            limit=config.connection_pool_size,
            limit_per_host=config.connection_pool_size,
            keepalive_timeout=60,
            enable_cleanup_closed=True,
            force_close=False  # Critical: keep connections alive
        )

        # Fix 2: Use asyncio.Semaphore instead of manual counter
        self.request_semaphore = asyncio.Semaphore(config.max_concurrent_requests)

        # Session pool management
        self.session_pool = []
        self.pool_lock = Lock()

        # Fix 4: OrderedDict for cache eviction clarity
        from collections import OrderedDict
        self.response_cache = OrderedDict()  # Clear LRU cache
        self.stats = {
            "requests": 0,
            "cache_hits": 0,
            "timeouts": 0,
            "successes": 0
        }

        logger.info(f"Optimized Advisor initialized: model={config.advisor_model}, pool_size={config.connection_pool_size}")

    async def get_session(self) -> aiohttp.ClientSession:
        """Get session from pool with shared connector (Fix 1)"""
        async with self.pool_lock:
            if self.session_pool:
                return self.session_pool.pop()
            else:
                # Create session with shared connector
                timeout = aiohttp.ClientTimeout(total=self.config.advisor_timeout)
                return aiohttp.ClientSession(
                    connector=self.shared_connector,
                    timeout=timeout,
                    connector_owner=False  # Critical: don't close shared connector
                )

    async def return_session(self, session: aiohttp.ClientSession):
        """Return a session to the pool"""
        async with self.pool_lock:
            if len(self.session_pool) < self.config.connection_pool_size:
                self.session_pool.append(session)
            else:
                await session.close()

    def is_question(self, text: str) -> bool:
        """Fast regex check if text contains a question"""
        return bool(self.question_regex.search(text.strip()))

    def _get_cache_key(self, text: str) -> str:
        """Generate cache key for common questions"""
        # Simple normalization for caching
        normalized = re.sub(r'[^\w\s]', '', text.lower()).strip()
        return normalized[:50]  # Limit key length

    async def _call_ollama_optimized(self, prompt: str) -> Optional[str]:
        """Optimized Ollama call with connection pooling and caching"""
        self.stats["requests"] += 1

        # Check cache first
        cache_key = self._get_cache_key(prompt)
        if cache_key in self.response_cache:
            self.stats["cache_hits"] += 1
            logger.debug(f"Cache hit for: {cache_key}")
            return self.response_cache[cache_key]

        # Rate limiting check
        if self.active_requests >= self.max_concurrent:
            logger.warning("Too many concurrent requests, throttling")
            await asyncio.sleep(0.1)
            return None

        self.active_requests += 1

        try:
            # Sprint 8: Optimized payload for speed
            payload = {
                "model": self.config.advisor_model,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.1,     # Lower for consistency and speed
                    "top_k": 5,             # Very focused for speed
                    "top_p": 0.7,           # Reduced for speed
                    "num_predict": 40,      # Very short responses
                    "stop": ["\n\n", "•", "-", "1."],  # Stop early
                    "num_ctx": 512          # Reduced context window
                }
            }

            session = await self.get_session()

            try:
                async with session.post(self.ollama_url, json=payload) as response:
                    if response.status == 200:
                        result = await response.json()
                        response_text = result.get('response', '').strip()

                        # Cache successful responses
                        if response_text and len(response_text) > 10:
                            self.response_cache[cache_key] = response_text
                            # Limit cache size
                            if len(self.response_cache) > 50:
                                oldest_key = next(iter(self.response_cache))
                                del self.response_cache[oldest_key]

                        self.stats["successes"] += 1
                        return response_text
                    else:
                        logger.error(f"Ollama API error: {response.status}")
                        return None
            finally:
                await self.return_session(session)

        except asyncio.TimeoutError:
            self.stats["timeouts"] += 1
            logger.warning(f"Ollama timeout ({self.config.advisor_timeout}s)")
            return None
        except Exception as e:
            logger.error(f"Ollama error: {e}")
            return None
        finally:
            self.active_requests -= 1

    def _build_optimized_prompt(self, question: str, context: Dict[str, Any]) -> str:
        """Sprint 8: Ultra-fast prompt optimized for phi3:mini"""
        # Much shorter prompt for speed
        return f"Q: {question}\nA: •"

    async def process_hot_stream_text(self, text: str) -> Optional[str]:
        """Process incoming hot stream text with optimized performance"""
        if not self.is_question(text):
            return None

        start_time = time.time()

        # Get minimal context for speed
        context = self.chronicler.get_context_dict() if self.config.chronicler_enabled else {}

        # Build ultra-fast prompt
        prompt = self._build_optimized_prompt(text, context)

        # Call optimized Ollama
        response = await self._call_ollama_optimized(prompt)

        response_time = time.time() - start_time
        self.last_response_time = response_time

        if response:
            # Sprint 8: Format response consistently
            if not response.startswith('•'):
                response = f"• {response}"

            logger.info(f"⚡ Optimized response in {response_time:.3f}s: {response}")
            return response
        else:
            logger.warning(f"❌ No response from Optimized Advisor for: {text}")
            return None

    async def close(self):
        """Fix 6: Graceful shutdown - close all sessions"""
        async with self.pool_lock:
            for session in self.session_pool:
                if not session.closed:
                    await session.close()
            self.session_pool.clear()

        # Close the shared connector
        if self.shared_connector and not self.shared_connector.closed:
            await self.shared_connector.close()

    def get_performance_stats(self) -> Dict[str, Any]:
        """Get performance statistics"""
        cache_hit_rate = (self.stats["cache_hits"] / max(self.stats["requests"], 1)) * 100
        success_rate = (self.stats["successes"] / max(self.stats["requests"], 1)) * 100

        return {
            "requests": self.stats["requests"],
            "cache_hit_rate": f"{cache_hit_rate:.1f}%",
            "success_rate": f"{success_rate:.1f}%",
            "timeouts": self.stats["timeouts"],
            "last_response_time": f"{self.last_response_time:.3f}s",
            "cache_size": len(self.response_cache)
        }

# Use the same Chronicler from the original brain.py
from brain import Chronicler, CognitiveEngine

class OptimizedCognitiveEngine(CognitiveEngine):
    """Sprint 8: Performance-optimized Cognitive Engine"""

    def __init__(self, config: OptimizedCognitiveConfig):
        # Initialize with optimized config
        self.config = config
        self.chronicler = Chronicler(config) if config.chronicler_enabled else None
        self.advisor = OptimizedAdvisor(config, self.chronicler)
        self.running = False
        self.whisper_ws = None
        self.reconnect_delay = 1.0
        self.max_reconnect_delay = 10.0
        self.stats = {
            "questions_processed": 0,
            "context_updates": 0,
            "average_response_time": 0.0,
            "whisper_reconnects": 0
        }

        logger.info("🚀 Optimized Cognitive Engine initialized for Sprint 8")

    async def _stats_reporter(self):
        """Enhanced stats reporting with performance metrics"""
        while self.running:
            await asyncio.sleep(30.0)
            if self.running:
                advisor_stats = self.advisor.get_performance_stats()
                logger.info(f"📊 Sprint 8 Stats: {self.stats['questions_processed']} questions, "
                          f"last response: {advisor_stats['last_response_time']}, "
                          f"cache hits: {advisor_stats['cache_hit_rate']}, "
                          f"success rate: {advisor_stats['success_rate']}")

async def main():
    """Sprint 8 main entry point with simplified testing"""
    print("🚀 Sprint 8: Optimized Cognitive Engine")
    print("=" * 50)

    config = OptimizedCognitiveConfig()
    config.advisor_model = "phi3:mini"  # Force fast model for testing

    # Create a simple chronicler for testing
    from brain import Chronicler
    chronicler = Chronicler(config)
    advisor = OptimizedAdvisor(config, chronicler)

    test_questions = [
        "What is TCP?",
        "How does HTTP work?",
        "What are APIs?",
        "What is TCP?"  # Test caching
    ]

    print("Testing optimized performance...")

    for i, question in enumerate(test_questions, 1):
        print(f"\nTest {i}: {question}")
        start_time = time.time()

        response = await advisor.process_hot_stream_text(question)
        end_time = time.time()

        if response:
            print(f"✅ Response ({(end_time-start_time)*1000:.1f}ms): {response}")
        else:
            print(f"❌ No response")

    # Print performance stats
    stats = advisor.get_performance_stats()
    print(f"\n📊 Performance Stats:")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    # Fix 6: Always cleanup on exit
    print("\n🧹 Cleaning up connections...")
    try:
        await advisor.close()
        print("✅ Graceful shutdown complete")
    except Exception as e:
        print(f"⚠️  Cleanup warning: {e}")

if __name__ == "__main__":
    asyncio.run(main())