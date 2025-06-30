#!/usr/bin/env python3
"""
Real Speech Audio Generator for Sprint 1.1
===========================================

This script generates actual human speech audio files for valid transcription testing.
Uses Google Text-to-Speech to create real speech that will trigger Whisper's neural network.
"""

import os
import numpy as np
from gtts import gTTS
import soundfile as sf
from pydub import AudioSegment
import io
import tempfile

def create_real_speech_files():
    """Generate real speech audio files for transcription testing"""

    print("🎤 Generating Real Speech Audio Files...")

    # Test phrases - carefully chosen for transcription testing
    test_phrases = {
        "short_speech.wav": {
            "text": "test",
            "description": "Single word (PRIMARY TEST)",
            "target_duration": 1.0
        },
        "medium_speech.wav": {
            "text": "hello world how are you today",
            "description": "Short phrase (SECONDARY TEST)",
            "target_duration": 3.0
        },
        "clear_speech.wav": {
            "text": "the quick brown fox jumps over the lazy dog",
            "description": "Clear pronunciation test",
            "target_duration": 4.0
        }
    }

    for filename, config in test_phrases.items():
        print(f"\n📝 Creating {filename}: '{config['text']}'")
        print(f"   Purpose: {config['description']}")

        try:
            # Generate speech using Google TTS
            tts = gTTS(text=config["text"], lang='en', slow=False)

            # Save to temporary file
            with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as temp_file:
                tts.save(temp_file.name)
                temp_mp3_path = temp_file.name

            # Load and convert to proper format for Whisper
            audio = AudioSegment.from_mp3(temp_mp3_path)

            # Convert to 16kHz mono (Whisper's expected format)
            audio = audio.set_frame_rate(16000).set_channels(1)

            # Ensure minimum duration (Whisper needs >=1000ms)
            min_duration_ms = max(1000, int(config["target_duration"] * 1000))
            if len(audio) < min_duration_ms:
                # Pad with silence if too short
                silence_needed = min_duration_ms - len(audio)
                silence = AudioSegment.silent(duration=silence_needed)
                audio = audio + silence
                print(f"   ⏱️  Padded to {min_duration_ms}ms (was {len(audio)}ms)")

            # Export as WAV
            audio.export(filename, format="wav")

            # Verify the file
            data, sample_rate = sf.read(filename)
            duration = len(data) / sample_rate

            print(f"   ✅ Created: {duration:.2f}s, {sample_rate}Hz, {len(data.shape)} channel(s)")
            print(f"   📄 File size: {os.path.getsize(filename)} bytes")

            # Clean up temp file
            os.unlink(temp_mp3_path)

        except Exception as e:
            print(f"   ❌ Error creating {filename}: {e}")

    # Also create the silence file for VAD validation
    print(f"\n🔇 Creating silence.wav for VAD validation...")
    silence_duration = 1.5  # 1.5 seconds of silence
    sample_rate = 16000
    silence = np.zeros(int(sample_rate * silence_duration))
    sf.write("silence.wav", silence, sample_rate)
    print(f"   ✅ Created: {silence_duration}s of pure silence")

    print(f"\n🎯 Real Speech Audio Generation Complete!")
    print(f"   Files ready for Sprint 1.1 transcription testing")

if __name__ == "__main__":
    create_real_speech_files()