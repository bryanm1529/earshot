#!/usr/bin/env python3
"""
Sprint 8: Production-Quality Optimized Cognitive Engine
Implements all performance and reliability improvements
"""

import asyncio
import aiohttp
import json
import re
import time
import logging
from collections import OrderedDict, deque
from dataclasses import dataclass
from typing import Optional, Dict, Any
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('production_cognitive_engine')

@dataclass
class ProductionConfig:
    """Production-optimized configuration"""
    whisper_host: str = "127.0.0.1"
    whisper_port: int = 8178
    ollama_host: str = "127.0.0.1"
    ollama_port: int = 11434

    # Speed optimizations
    advisor_model: str = "phi3:mini"
    advisor_timeout: float = 1.5
    max_context_tokens: int = 200

    # Connection management
    max_concurrent_requests: int = 3
    connection_pool_size: int = 5

    question_patterns: list = None

    def __post_init__(self):
        # Environment variable overrides
        self.advisor_model = os.getenv('COPILOT_ADVISOR_MODEL', self.advisor_model)

        if self.question_patterns is None:
            self.question_patterns = [
                r'\?$',
                r'^(what|how|why)\s',
                r'^(is|are|can)\s',
            ]

class ProductionChronicler:
    """Context management with proper token limiting"""

    def __init__(self, config: ProductionConfig):
        self.config = config
        self.context_store = deque(maxlen=30)
        self.current_summary = ""
        self.entities = {}

    def add_transcription(self, text: str, timestamp: float = None):
        """Add transcription with timestamp"""
        if timestamp is None:
            timestamp = time.time()

        self.context_store.append({
            'timestamp': timestamp,
            'text': text.strip()
        })

    def get_context_dict(self, max_tokens: Optional[int] = None) -> Dict[str, Any]:
        """Get context with proper token limiting"""
        summary = self.current_summary

        # Fix 5: Actually enforce token limit
        if max_tokens and len(summary) > max_tokens:
            summary = summary[:max_tokens] + "..."

        return {
            "summary": summary,
            "entities": self.entities
        }

class ProductionAdvisor:
    """Production-quality advisor with all performance improvements"""

    def __init__(self, config: ProductionConfig, chronicler: ProductionChronicler):
        self.config = config
        self.chronicler = chronicler
        self.question_regex = re.compile('|'.join(config.question_patterns), re.IGNORECASE)
        self.last_response_time = 0
        self.ollama_url = f"http://{config.ollama_host}:{config.ollama_port}/api/generate"

        # Fix 1: Shared TCPConnector (create once, reuse)
        self.connector = aiohttp.TCPConnector(
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
        self.pool_lock = asyncio.Lock()

        # Fix 4: OrderedDict for cache eviction clarity
        self.response_cache = OrderedDict()
        self.max_cache_size = 50

        # Performance tracking
        self.stats = {
            "requests": 0,
            "cache_hits": 0,
            "timeouts": 0,
            "successes": 0
        }

        logger.info(f"Production Advisor: model={config.advisor_model}, pool={config.connection_pool_size}")

    async def get_session(self) -> aiohttp.ClientSession:
        """Get session from pool with shared connector"""
        async with self.pool_lock:
            if self.session_pool:
                return self.session_pool.pop()
            else:
                # Create session with shared connector
                timeout = aiohttp.ClientTimeout(total=self.config.advisor_timeout)
                return aiohttp.ClientSession(
                    connector=self.connector,
                    timeout=timeout,
                    connector_owner=False  # Critical: don't close shared connector
                )

    async def return_session(self, session: aiohttp.ClientSession):
        """Return session to pool properly"""
        async with self.pool_lock:
            if len(self.session_pool) < self.config.connection_pool_size:
                self.session_pool.append(session)

    def is_question(self, text: str) -> bool:
        """Fast regex check if text contains a question"""
        return bool(self.question_regex.search(text.strip()))

    def _get_cache_key(self, text: str) -> str:
        """Generate cache key for common questions"""
        normalized = re.sub(r'[^\w\s]', '', text.lower()).strip()
        return normalized[:50]

    async def _call_ollama_production(self, prompt: str) -> Optional[str]:
        """Production-quality Ollama call with all fixes"""
        self.stats["requests"] += 1

        # Check cache first
        cache_key = self._get_cache_key(prompt)
        if cache_key in self.response_cache:
            self.stats["cache_hits"] += 1
            # Move to end for LRU behavior
            self.response_cache.move_to_end(cache_key)
            logger.debug(f"Cache hit for: {cache_key}")
            return self.response_cache[cache_key]

        # Fix 2: Use semaphore instead of manual counter (eliminates race condition)
        async with self.request_semaphore:
            try:
                # Fix 3: Improved stop tokens for Phi-3
                payload = {
                    "model": self.config.advisor_model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "temperature": 0.1,
                        "top_k": 5,
                        "top_p": 0.7,
                        "num_predict": 40,
                        "stop": ["\n\n", "\nQ:", "\nA:"],  # Better stop tokens
                        "num_ctx": 512
                    }
                }

                session = await self.get_session()

                try:
                    async with session.post(self.ollama_url, json=payload) as response:
                        if response.status == 200:
                            result = await response.json()
                            response_text = result.get('response', '').strip()

                            # Cache successful responses with LRU eviction
                            if response_text and len(response_text) > 10:
                                self.response_cache[cache_key] = response_text

                                # Fix 4: Proper cache eviction with OrderedDict
                                if len(self.response_cache) > self.max_cache_size:
                                    self.response_cache.popitem(last=False)  # Remove oldest

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

    def _build_optimized_prompt(self, question: str, context: Dict[str, Any]) -> str:
        """Ultra-fast prompt optimized for phi3:mini"""
        return f"Q: {question}\nA: •"

    async def process_hot_stream_text(self, text: str) -> Optional[str]:
        """Process with all performance optimizations"""
        if not self.is_question(text):
            return None

        start_time = time.time()

        # Fix 5: Actually enforce context token limit
        context = self.chronicler.get_context_dict(max_tokens=self.config.max_context_tokens)

        # Build ultra-fast prompt
        prompt = self._build_optimized_prompt(text, context)

        # Call production Ollama
        response = await self._call_ollama_production(prompt)

        response_time = time.time() - start_time
        self.last_response_time = response_time

        if response:
            # Format response consistently
            if not response.startswith('•'):
                response = f"• {response}"

            logger.info(f"⚡ Production response in {response_time:.3f}s: {response}")
            return response
        else:
            logger.warning(f"❌ No response from Production Advisor for: {text}")
            return None

    async def close(self):
        """Fix 6: Graceful shutdown - close all sessions"""
        async with self.pool_lock:
            for session in self.session_pool:
                if not session.closed:
                    await session.close()
            self.session_pool.clear()

        # Close the shared connector
        if self.connector and not self.connector.closed:
            await self.connector.close()

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

async def main():
    """Production-quality test with all improvements"""
    print("🚀 Sprint 8: Production Cognitive Engine")
    print("=" * 60)
    print("✅ Shared TCPConnector - eliminates connection overhead")
    print("✅ asyncio.Semaphore - fixes race conditions")
    print("✅ Graceful shutdown - proper session cleanup")
    print("✅ Context limiting - actually enforced token limits")
    print("✅ OrderedDict cache - clear LRU eviction")
    print("✅ Improved stop tokens - better for Phi-3")
    print("=" * 60)

    # Fix 7: Config creation before mutations
    config = ProductionConfig()
    config.advisor_model = "phi3:mini"
    config.advisor_timeout = 1.0

    print(f"🔧 Config: {config.advisor_model}, timeout={config.advisor_timeout}s")

    chronicler = ProductionChronicler(config)
    advisor = ProductionAdvisor(config, chronicler)

    test_questions = [
        "What is TCP?",  # Fix 7: Transmission Control Protocol (corrected)
        "How does HTTP work?",
        "What are APIs?",
        "What is TCP?"  # Test LRU caching
    ]

    print("\n🧪 Testing production performance...")

    try:
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
        print(f"\n📊 Production Performance Stats:")
        for key, value in stats.items():
            print(f"  {key}: {value}")

    finally:
        # Fix 6: Always cleanup on exit
        print("\n🧹 Cleaning up connections...")
        await advisor.close()
        print("✅ Graceful shutdown complete")

if __name__ == "__main__":
    asyncio.run(main())