#!/usr/bin/env python3
"""
WebSocket Whisper Test Client
Tests the WebSocket functionality of the whisper server by streaming a WAV file
and receiving real-time transcription results.
"""

import asyncio
import websockets
import json
import wave
import struct
import sys
import argparse
import time
from pathlib import Path

class WhisperWebSocketClient:
    def __init__(self, server_host="127.0.0.1", server_port=9080):
        self.server_host = server_host
        self.server_port = server_port
        self.websocket = None

    async def connect(self):
        """Connect to the WebSocket server"""
        uri = f"ws://{self.server_host}:{self.server_port}/hot_stream"
        print(f"Connecting to {uri}...")

        try:
            self.websocket = await websockets.connect(uri)
            print("✅ Connected to WebSocket server")
            return True
        except Exception as e:
            print(f"❌ Failed to connect: {e}")
            return False

    async def send_ping(self):
        """Send a ping message to test text communication"""
        if not self.websocket:
            return False

        ping_msg = {"type": "ping"}
        await self.websocket.send(json.dumps(ping_msg))
        print("📤 Sent ping message")
        return True

    async def send_wav_file(self, wav_file_path, chunk_size_ms=100):
        """Send a WAV file in chunks to simulate real-time streaming"""
        if not self.websocket:
            print("❌ Not connected to server")
            return False

        if not Path(wav_file_path).exists():
            print(f"❌ WAV file not found: {wav_file_path}")
            return False

        try:
            with wave.open(wav_file_path, 'rb') as wav_file:
                # Get WAV file properties
                channels = wav_file.getnchannels()
                sample_width = wav_file.getsampwidth()
                framerate = wav_file.getframerate()
                total_frames = wav_file.getnframes()

                print(f"📄 WAV file info:")
                print(f"   - Channels: {channels}")
                print(f"   - Sample width: {sample_width} bytes")
                print(f"   - Frame rate: {framerate} Hz")
                print(f"   - Total frames: {total_frames}")
                print(f"   - Duration: {total_frames/framerate:.2f} seconds")

                if sample_width != 2:
                    print("❌ Only 16-bit WAV files are supported")
                    return False

                if channels != 1:
                    print("⚠️  Warning: Multi-channel audio detected, using first channel only")

                # Calculate chunk size in frames
                chunk_frames = int((chunk_size_ms / 1000.0) * framerate)
                chunk_bytes = chunk_frames * channels * sample_width

                print(f"🎵 Streaming audio in {chunk_size_ms}ms chunks ({chunk_frames} frames, {chunk_bytes} bytes each)")
                print("📤 Starting audio stream...")

                frames_sent = 0
                while frames_sent < total_frames:
                    # Read a chunk of audio data
                    frames_to_read = min(chunk_frames, total_frames - frames_sent)
                    audio_data = wav_file.readframes(frames_to_read)

                    if not audio_data:
                        break

                    # If multi-channel, extract only the first channel
                    if channels > 1:
                        # Convert to numpy-like processing
                        samples = struct.unpack(f'<{len(audio_data)//2}h', audio_data)
                        mono_samples = samples[::channels]  # Take every nth sample (first channel)
                        audio_data = struct.pack(f'<{len(mono_samples)}h', *mono_samples)

                    # Send binary audio data
                    await self.websocket.send(audio_data)
                    frames_sent += frames_to_read

                    progress = (frames_sent / total_frames) * 100
                    print(f"📤 Sent chunk {frames_sent//chunk_frames + 1}: {progress:.1f}% complete")

                    # Simulate real-time streaming delay
                    await asyncio.sleep(chunk_size_ms / 1000.0)

                print("✅ Finished sending audio file")
                return True

        except Exception as e:
            print(f"❌ Error sending WAV file: {e}")
            return False

    async def listen_for_responses(self, timeout=30):
        """Listen for transcription responses from the server"""
        if not self.websocket:
            return

        print(f"👂 Listening for responses (timeout: {timeout}s)...")
        start_time = time.time()

        try:
            while True:
                # Check timeout
                if time.time() - start_time > timeout:
                    print(f"⏰ Timeout reached ({timeout}s)")
                    break

                try:
                    # Wait for message with short timeout
                    message = await asyncio.wait_for(self.websocket.recv(), timeout=1.0)

                    try:
                        # Try to parse as JSON
                        data = json.loads(message)
                        if data.get("type") == "pong":
                            print("📥 Received pong response")
                        elif "text" in data:
                            print(f"📝 Transcription: '{data['text']}'")
                            if data.get("timestamp"):
                                print(f"   Timestamp: {data['timestamp']}")
                        else:
                            print(f"📥 Received: {data}")
                    except json.JSONDecodeError:
                        # Not JSON, treat as plain text
                        print(f"📥 Received (text): {message}")

                except asyncio.TimeoutError:
                    continue  # Continue listening

        except websockets.exceptions.ConnectionClosed:
            print("🔌 Connection closed by server")
        except Exception as e:
            print(f"❌ Error while listening: {e}")

    async def close(self):
        """Close the WebSocket connection"""
        if self.websocket:
            await self.websocket.close()
            print("🔌 Disconnected from server")

async def main():
    parser = argparse.ArgumentParser(description="WebSocket Whisper Test Client")
    parser.add_argument("--host", default="127.0.0.1", help="Server hostname")
    parser.add_argument("--port", type=int, default=9080, help="Server WebSocket port")
    parser.add_argument("--wav-file", required=True, help="WAV file to stream")
    parser.add_argument("--chunk-ms", type=int, default=100, help="Chunk size in milliseconds")
    parser.add_argument("--timeout", type=int, default=30, help="Response timeout in seconds")

    args = parser.parse_args()

    client = WhisperWebSocketClient(args.host, args.port)

    try:
        # Connect to server
        if not await client.connect():
            return 1

        # Create tasks for sending and receiving
        send_task = asyncio.create_task(client.send_wav_file(args.wav_file, args.chunk_ms))
        listen_task = asyncio.create_task(client.listen_for_responses(args.timeout))

        # Run both tasks concurrently
        await asyncio.gather(send_task, listen_task)

    except KeyboardInterrupt:
        print("\n⚠️  Interrupted by user")
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    finally:
        await client.close()

    print("✅ Test completed")
    return 0

if __name__ == "__main__":
    sys.exit(asyncio.run(main()))