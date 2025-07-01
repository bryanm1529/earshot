#!/usr/bin/env python3
"""
Test script for the new Python-Native architecture
Validates all components without running the full system
"""

import asyncio
import os
import subprocess
import tempfile
import wave
import aiohttp
import json

async def test_whisper_cli():
    """Test that whisper CLI is available and works"""
    print("🔍 Testing Whisper CLI...")

    whisper_exe = "whisper.cpp/build/bin/Release/whisper-cli.exe"
    model_path = "whisper.cpp/models/for-tests-ggml-tiny.en.bin"

    # Check if files exist
    if not os.path.exists(whisper_exe):
        print(f"❌ Whisper executable not found: {whisper_exe}")
        return False

    if not os.path.exists(model_path):
        print(f"❌ Whisper model not found: {model_path}")
        return False

    print(f"✅ Whisper executable found: {whisper_exe}")
    print(f"✅ Whisper model found: {model_path}")

    # Test help command
    try:
        result = subprocess.run([whisper_exe, "--help"],
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print("✅ Whisper CLI responds to --help")
            return True
        else:
            print(f"❌ Whisper CLI --help failed: {result.stderr}")
            return False
    except Exception as e:
        print(f"❌ Error testing whisper CLI: {e}")
        return False

async def test_ollama_connection():
    """Test Ollama API connection"""
    print("🔍 Testing Ollama connection...")

    try:
        timeout = aiohttp.ClientTimeout(total=5)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get("http://127.0.0.1:11434/api/tags") as response:
                if response.status == 200:
                    data = await response.json()
                    models = [model['name'] for model in data.get('models', [])]
                    print(f"✅ Ollama is running with models: {models}")
                    return True
                else:
                    print(f"❌ Ollama responded with status {response.status}")
                    return False
    except Exception as e:
        print(f"❌ Ollama connection failed: {e}")
        print("   Make sure Ollama is running: ollama serve")
        return False

async def test_ffmpeg():
    """Test ffmpeg availability"""
    print("🔍 Testing ffmpeg...")

    try:
        result = subprocess.run(["ffmpeg", "-version"],
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print("✅ ffmpeg is available")
            return True
        else:
            print(f"❌ ffmpeg test failed: {result.stderr}")
            return False
    except FileNotFoundError:
        print("❌ ffmpeg not found in PATH")
        print("   Install ffmpeg: https://ffmpeg.org/download.html")
        return False
    except Exception as e:
        print(f"❌ Error testing ffmpeg: {e}")
        return False

def test_audio_device():
    """Test audio device availability"""
    print("🔍 Testing audio device...")

    device_name = "CABLE Output (VB-Audio Virtual Cable)"

    try:
        # Run ffmpeg to list audio devices
        result = subprocess.run([
            "ffmpeg", "-f", "dshow", "-list_devices", "true", "-i", "dummy"
        ], capture_output=True, text=True, timeout=10)

        # Check if our device is in the output
        if device_name in result.stderr:
            print(f"✅ Audio device found: {device_name}")
            return True
        else:
            print(f"❌ Audio device not found: {device_name}")
            print("   Available devices in ffmpeg output:")
            for line in result.stderr.split('\n'):
                if 'DirectShow' in line and 'audio' in line.lower():
                    print(f"     {line.strip()}")
            return False

    except Exception as e:
        print(f"❌ Error testing audio device: {e}")
        return False

async def test_whisper_with_sample():
    """Test whisper CLI with a small sample audio file"""
    print("🔍 Testing Whisper with sample audio...")

    whisper_exe = "whisper.cpp/build/bin/Release/whisper-cli.exe"
    model_path = "whisper.cpp/models/for-tests-ggml-tiny.en.bin"

    # Create a simple test audio file (1 second of silence)
    try:
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
            temp_filename = temp_file.name

            # Create 1 second of silence at 16kHz
            sample_rate = 16000
            duration = 1  # 1 second
            frames = sample_rate * duration
            silence = b'\x00\x00' * frames  # 16-bit silence

            with wave.open(temp_filename, 'wb') as wav_file:
                wav_file.setnchannels(1)  # Mono
                wav_file.setsampwidth(2)  # 16-bit
                wav_file.setframerate(sample_rate)
                wav_file.writeframes(silence)

        # Run whisper on the test file
        cmd = [
            whisper_exe,
            "-m", model_path,
            "-l", "en",
            "--no-timestamps",
            "--output-txt",
            "--no-prints",
            temp_filename
        ]

        result = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await result.communicate()

        if result.returncode == 0:
            print("✅ Whisper CLI processes audio files successfully")

            # Check if output file was created
            output_file = temp_filename + ".txt"
            if os.path.exists(output_file):
                with open(output_file, 'r') as f:
                    content = f.read().strip()
                print(f"   Output: '{content}' (expected silence/empty)")
                os.unlink(output_file)

            # Clean up
            os.unlink(temp_filename)
            return True
        else:
            print(f"❌ Whisper CLI failed: {stderr.decode()}")
            os.unlink(temp_filename)
            return False

    except Exception as e:
        print(f"❌ Error testing whisper with sample: {e}")
        return False

async def main():
    """Run all tests"""
    print("🚀 Testing Python-Native Architecture Setup")
    print("=" * 50)

    tests = [
        ("Whisper CLI", test_whisper_cli()),
        ("Ollama Connection", test_ollama_connection()),
        ("FFmpeg", test_ffmpeg()),
        ("Audio Device", test_audio_device()),
        ("Whisper Sample", test_whisper_with_sample())
    ]

    results = []
    for test_name, test_coro in tests:
        print(f"\n{test_name}:")
        try:
            result = await test_coro if asyncio.iscoroutine(test_coro) else test_coro
            results.append((test_name, result))
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
            results.append((test_name, False))

    print("\n" + "=" * 50)
    print("📊 Test Results:")

    all_passed = True
    for test_name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {test_name}: {status}")
        if not passed:
            all_passed = False

    print("=" * 50)
    if all_passed:
        print("🎉 ALL TESTS PASSED! Ready to run the native architecture.")
        print("   Run: ../start_simple.ps1")
    else:
        print("⚠️  Some tests failed. Fix the issues above before proceeding.")

    return all_passed

if __name__ == "__main__":
    asyncio.run(main())