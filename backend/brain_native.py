#!/usr/bin/env python3
"""
Python-Native Pipeline: The Strategic Pivot
Eliminates C++ WebSocket server entirely and uses robust subprocess management
"""

import asyncio
import aiohttp
import json
import re
import time
import logging
import os
import tempfile
import wave
from collections import deque
from dataclasses import dataclass
from typing import Optional, Dict, Any, Set
import argparse
import websockets
import signal

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('cognitive_engine_native')

@dataclass
class CognitiveConfig:
    """Configuration for the Native Cognitive Engine"""
    # No more whisper server - we manage subprocesses directly
    ollama_host: str = "127.0.0.1"
    ollama_port: int = 11434

    # Frontend WebSocket server (unchanged)
    frontend_ws_host: str = "127.0.0.1"
    frontend_ws_port: int = 9082

    # Audio processing configuration
    audio_device: str = "CABLE Output (VB-Audio Virtual Cable)"
    sample_rate: int = 16000
    channels: int = 1

    # Whisper CLI configuration
    whisper_model: str = "whisper.cpp/models/for-tests-ggml-tiny.en.bin"
    whisper_executable: str = "whisper.cpp/build/bin/Release/whisper-cli.exe"
    whisper_threads: int = 4

    # Chronicler settings
    context_max_length: int = 50
    summarization_timer: float = 5.0

    # Advisor settings
    advisor_model: str = "llama3:8b"
    question_patterns: list = None
    advisor_timeout: float = 0.7
    max_context_tokens: int = 300

    def __post_init__(self):
        # Environment variable overrides
        self.advisor_model = os.getenv('COPILOT_ADVISOR_MODEL', self.advisor_model)
        self.chronicler_enabled = os.getenv('COPILOT_CHRONICLER_ENABLED', 'true').lower() == 'true'

        if self.question_patterns is None:
            self.question_patterns = [
                r'\?$',
                r'^(what|how|why|when|where|who)\s',
                r'^(is|are|can|could|should|would)\s',
                r'^(do|does|did)\s',
                r'^(tell me|explain)',
            ]

        logger.info(f"🔧 Native Config: Advisor model={self.advisor_model}")
        logger.info(f"🔧 Audio device: {self.audio_device}")
        logger.info(f"🔧 Whisper model: {self.whisper_model}")

class FrontendWebSocketServer:
    """
    WebSocket server for frontend communication (unchanged from original)
    """

    def __init__(self, config: CognitiveConfig):
        self.config = config
        self.clients: Set[websockets.WebSocketServerProtocol] = set()
        self.server = None
        self.is_paused = False

        logger.info(f"Frontend WebSocket server initialized on {config.frontend_ws_host}:{config.frontend_ws_port}")

    async def start_server(self):
        """Start the WebSocket server"""
        try:
            self.server = await websockets.serve(
                self.handle_client,
                self.config.frontend_ws_host,
                self.config.frontend_ws_port,
                ping_interval=10,
                ping_timeout=10
            )
            logger.info(f"🌐 Frontend WebSocket server started on ws://{self.config.frontend_ws_host}:{self.config.frontend_ws_port}")
        except Exception as e:
            logger.error(f"Failed to start frontend WebSocket server: {e}")
            raise

    async def handle_client(self, websocket: websockets.WebSocketServerProtocol):
        """Handle new client connection"""
        client_addr = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        try:
            logger.info(f"🔌 Frontend client connected: {client_addr}")
            self.clients.add(websocket)

            # Send initial status
            await self.send_to_client(websocket, {
                "type": "status",
                "status": "connected",
                "paused": self.is_paused,
                "timestamp": int(time.time() * 1000)
            })

            # Handle messages
            while True:
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                    data = json.loads(message)
                    await self.handle_client_message(websocket, data)
                except asyncio.TimeoutError:
                    continue
                except websockets.exceptions.ConnectionClosed:
                    logger.info(f"Client {client_addr} closed cleanly")
                    break
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON from {client_addr}: {message}")
                except Exception as e:
                    logger.error(f"Error handling message from {client_addr}: {e}")

        except Exception:
            logger.exception("❌ Unhandled error in WebSocket handler")
        finally:
            self.clients.discard(websocket)

    async def handle_client_message(self, websocket: websockets.WebSocketServerProtocol, data: Dict[str, Any]):
        """Handle incoming messages from frontend clients"""
        msg_type = data.get('type')

        if msg_type == 'ping':
            await self.send_to_client(websocket, {
                "type": "pong",
                "timestamp": int(time.time() * 1000)
            })
        elif msg_type == 'pause':
            self.is_paused = True
            await self.broadcast_status()
            logger.info("🚫 System paused by frontend")
        elif msg_type == 'resume':
            self.is_paused = False
            await self.broadcast_status()
            logger.info("▶️ System resumed by frontend")

    async def send_to_client(self, websocket: websockets.WebSocketServerProtocol, data: Dict[str, Any]):
        """Send data to a specific client"""
        try:
            message = json.dumps(data)
            await websocket.send(message)
        except websockets.exceptions.ConnectionClosed:
            self.clients.discard(websocket)
        except Exception as e:
            logger.error(f"Error sending to client: {e}")
            self.clients.discard(websocket)

    async def broadcast_advisor_keywords(self, text: str):
        """Broadcast advisor keywords to all connected clients"""
        if self.is_paused:
            logger.debug("System paused, not broadcasting")
            return

        if not self.clients:
            return

        message = {
            "type": "advisor_keywords",
            "text": text,
            "timestamp": int(time.time() * 1000)
        }

        disconnected = set()
        for client in self.clients:
            try:
                await self.send_to_client(client, message)
            except Exception:
                disconnected.add(client)

        self.clients -= disconnected

        if self.clients:
            logger.info(f"🎯 Broadcast to {len(self.clients)} client(s): {text}")

    async def broadcast_status(self):
        """Broadcast current system status to all clients"""
        if not self.clients:
            return

        message = {
            "type": "status",
            "status": "connected",
            "paused": self.is_paused,
            "timestamp": int(time.time() * 1000)
        }

        for client in list(self.clients):
            await self.send_to_client(client, message)

    async def stop_server(self):
        """Stop the WebSocket server"""
        if self.server:
            self.server.close()
            await self.server.wait_closed()
            logger.info("🌐 Frontend WebSocket server stopped")

class Chronicler:
    """
    Conversational Memory System (unchanged from original)
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

        self.context_store.append({
            'timestamp': time.time(),
            'text': self.pending_text.strip()
        })

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
    Real-time Assistance Engine (unchanged from original)
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
                "num_predict": 100
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

    async def process_text(self, text: str) -> Optional[str]:
        """Process incoming text and generate advice if needed"""
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

class AudioPipeline:
    """
    NEW: Python-native audio pipeline using subprocess management
    This replaces the problematic C++ WebSocket server entirely
    """

    def __init__(self, config: CognitiveConfig):
        self.config = config
        self.ffmpeg_proc = None
        self.running = False

        # Audio buffer for accumulating samples
        self.audio_buffer = bytearray()
        self.chunk_size = 1024 * 16  # 16KB chunks for processing

        logger.info("Audio Pipeline initialized (Python-native)")

    async def start_pipeline(self, transcript_callback):
        """Start the ffmpeg -> whisper pipeline"""
        self.running = True
        self.transcript_callback = transcript_callback

        try:
            # Step 1: Create ffmpeg command to capture audio and output raw PCM
            ffmpeg_cmd = [
                "ffmpeg",
                "-f", "dshow",
                "-i", f"audio={self.config.audio_device}",
                "-ac", str(self.config.channels),
                "-ar", str(self.config.sample_rate),
                "-acodec", "pcm_s16le",
                "-f", "s16le",
                "-"  # Output to stdout
            ]

            logger.info(f"🎙️ Starting audio capture: {' '.join(ffmpeg_cmd)}")

            # Start ffmpeg process
            self.ffmpeg_proc = await asyncio.create_subprocess_exec(
                *ffmpeg_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            # Process audio in chunks
            await self._process_audio_chunks()

        except Exception as e:
            logger.error(f"Pipeline error: {e}")
            await self.stop_pipeline()

    async def _process_audio_chunks(self):
        """Process audio data in chunks using temporary files"""
        chunk_counter = 0

        while self.running and self.ffmpeg_proc:
            try:
                # Read audio chunk from ffmpeg
                chunk = await self.ffmpeg_proc.stdout.read(self.chunk_size)
                if not chunk:
                    logger.warning("No more audio data from ffmpeg")
                    break

                self.audio_buffer.extend(chunk)

                # Process accumulated buffer when we have enough data (2 seconds worth)
                samples_needed = self.config.sample_rate * 2 * 2  # 2 seconds * 2 bytes per sample

                if len(self.audio_buffer) >= samples_needed:
                    chunk_counter += 1
                    await self._process_audio_buffer(chunk_counter)

                    # Keep last 1 second for continuity
                    overlap_size = self.config.sample_rate * 2
                    self.audio_buffer = self.audio_buffer[-overlap_size:]

            except Exception as e:
                if self.running:
                    logger.error(f"Error processing audio chunk: {e}")
                break

    async def _process_audio_buffer(self, chunk_id: int):
        """Process accumulated audio buffer with whisper"""
        try:
            # Create temporary WAV file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                temp_filename = temp_file.name

                # Write WAV header and data
                with wave.open(temp_filename, 'wb') as wav_file:
                    wav_file.setnchannels(self.config.channels)
                    wav_file.setsampwidth(2)  # 16-bit
                    wav_file.setframerate(self.config.sample_rate)
                    wav_file.writeframes(self.audio_buffer)

            # Process with whisper
            await self._run_whisper_on_file(temp_filename, chunk_id)

            # Clean up
            os.unlink(temp_filename)

        except Exception as e:
            logger.error(f"Error processing audio buffer: {e}")

    async def _run_whisper_on_file(self, audio_file: str, chunk_id: int):
        """Run whisper CLI on audio file"""
        try:
            whisper_cmd = [
                self.config.whisper_executable,
                "-m", self.config.whisper_model,
                "-l", "en",
                "-t", str(self.config.whisper_threads),
                "--no-timestamps",
                "--output-txt",
                "--no-prints",
                audio_file
            ]

            logger.debug(f"Running whisper on chunk {chunk_id}")

            # Run whisper
            proc = await asyncio.create_subprocess_exec(
                *whisper_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            stdout, stderr = await proc.communicate()

            if proc.returncode == 0:
                # Whisper saves output to [filename].txt
                output_file = audio_file + ".txt"
                if os.path.exists(output_file):
                    with open(output_file, 'r', encoding='utf-8') as f:
                        transcript = f.read().strip()

                    os.unlink(output_file)  # Clean up

                    if transcript and transcript != '[BLANK_AUDIO]':
                        await self.transcript_callback(transcript)
                else:
                    logger.debug(f"No transcript output for chunk {chunk_id}")
            else:
                logger.warning(f"Whisper failed for chunk {chunk_id}: {stderr.decode()}")

        except Exception as e:
            logger.error(f"Error running whisper: {e}")

    async def stop_pipeline(self):
        """Stop the audio pipeline"""
        self.running = False

        if self.ffmpeg_proc:
            try:
                self.ffmpeg_proc.terminate()
                await self.ffmpeg_proc.wait()
            except:
                pass
            self.ffmpeg_proc = None

        logger.info("🎙️ Audio pipeline stopped")

class NativeCognitiveEngine:
    """
    NEW: Native Python cognitive engine that manages everything through subprocesses
    This replaces the complex C++ WebSocket server approach
    """

    def __init__(self, config: CognitiveConfig):
        self.config = config
        self.chronicler = Chronicler(config)
        self.advisor = Advisor(config, self.chronicler)
        self.frontend_server = FrontendWebSocketServer(config)
        self.audio_pipeline = AudioPipeline(config)
        self.running = False

        self.stats = {
            "questions_processed": 0,
            "context_updates": 0,
            "transcripts_processed": 0,
            "average_response_time": 0.0
        }

        logger.info("Native Cognitive Engine initialized")

    async def start(self):
        """Start the complete native cognitive engine"""
        self.running = True
        logger.info("🧠 Starting Native Cognitive Engine...")

        # Start frontend WebSocket server
        await self.frontend_server.start_server()

        # Start background tasks
        tasks = [
            asyncio.create_task(self._run_audio_pipeline()),
            asyncio.create_task(self._chronicler_ticker()),
            asyncio.create_task(self._stats_reporter())
        ]

        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Shutting down Native Cognitive Engine...")
            await self.shutdown()

    async def _run_audio_pipeline(self):
        """Run the audio pipeline with automatic restart on failure"""
        while self.running:
            try:
                await self.audio_pipeline.start_pipeline(self._process_transcript)
            except Exception as e:
                logger.error(f"Audio pipeline failed: {e}")
                if self.running:
                    logger.info("Restarting audio pipeline in 5 seconds...")
                    await asyncio.sleep(5)

    async def _process_transcript(self, text: str):
        """Process incoming transcript from audio pipeline"""
        if not text or not self.running:
            return

        logger.info(f"🎤 Transcript: {text}")
        self.stats["transcripts_processed"] += 1

        # Add to chronicler for context
        if self.config.chronicler_enabled:
            self.chronicler.add_transcription(text)
            self.stats["context_updates"] += 1

        # Process with Advisor if it's a question
        if self.advisor.is_question(text):
            response = await self.advisor.process_text(text)
            if response:
                await self.frontend_server.broadcast_advisor_keywords(response)
                self.stats["questions_processed"] += 1

    async def _chronicler_ticker(self):
        """Context ticker: print current summary every 5 seconds"""
        while self.running:
            await asyncio.sleep(5.0)
            if self.running and self.config.chronicler_enabled:
                self.chronicler.debug_print_context()

    async def _stats_reporter(self):
        """Report system statistics"""
        while self.running:
            await asyncio.sleep(30.0)
            if self.running:
                logger.info(f"📊 Stats: {self.stats['transcripts_processed']} transcripts, "
                          f"{self.stats['questions_processed']} questions, "
                          f"avg response: {self.advisor.last_response_time:.3f}s, "
                          f"frontend clients: {len(self.frontend_server.clients)}")

    async def shutdown(self):
        """Clean shutdown of all components"""
        self.running = False

        # Stop audio pipeline
        await self.audio_pipeline.stop_pipeline()

        # Stop frontend server
        await self.frontend_server.stop_server()

        logger.info("✅ Native Cognitive Engine shutdown complete")

async def main():
    """Main entry point for the native cognitive engine"""
    parser = argparse.ArgumentParser(description="Native Cognitive Engine for Earshot")
    parser.add_argument("--frontend-host", default="127.0.0.1",
                       help="Frontend WebSocket server host")
    parser.add_argument("--frontend-port", type=int, default=9082,
                       help="Frontend WebSocket server port")
    parser.add_argument("--audio-device", default="CABLE Output (VB-Audio Virtual Cable)",
                       help="Audio input device name")
    parser.add_argument("--whisper-model", default="./backend/whisper.cpp/models/for-tests-ggml-tiny.en.bin",
                       help="Path to Whisper model file")
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
        ollama_host=args.ollama_host,
        ollama_port=args.ollama_port,
        frontend_ws_host=args.frontend_host,
        frontend_ws_port=args.frontend_port,
        audio_device=args.audio_device,
        whisper_model=args.whisper_model
    )

    # Start native cognitive engine
    engine = NativeCognitiveEngine(config)

    # Handle shutdown signals
    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(engine.shutdown())

    signal.signal(signal.SIGINT, lambda s, f: signal_handler())
    signal.signal(signal.SIGTERM, lambda s, f: signal_handler())

    await engine.start()

if __name__ == "__main__":
    asyncio.run(main())