#!/usr/bin/env python3
"""
Sprint 3 Native Audio Implementation Test
Tests the native system audio capture implementation
"""

import subprocess
import platform
import os
import requests
import time

def check_whisper_backend():
    """Check if Whisper backend is running"""
    try:
        response = requests.get('http://localhost:8080/', timeout=5)
        return response.status_code == 200
    except:
        return False

def check_system_audio_setup():
    """Check platform-specific system audio setup"""
    system = platform.system()

    if system == "Darwin":  # macOS
        print("🍎 macOS System Audio Check")
        print("Looking for BlackHole audio devices...")

        # Try to list audio devices (requires system_profiler or similar)
        try:
            result = subprocess.run(['system_profiler', 'SPAudioDataType'],
                                  capture_output=True, text=True, timeout=10)
            if 'BlackHole' in result.stdout:
                print("✅ BlackHole device found!")
                return True
            else:
                print("❌ BlackHole not found")
                print("📋 Setup Instructions:")
                print("   1. Download BlackHole from: https://github.com/ExistentialAudio/BlackHole")
                print("   2. Install BlackHole 2ch")
                print("   3. Configure Audio MIDI Setup to route system audio through BlackHole")
                return False
        except:
            print("⚠️  Could not check audio devices automatically")
            print("📋 Manual Check: Look for BlackHole in Audio MIDI Setup")
            return None

    elif system == "Windows":
        print("🪟 Windows System Audio Check")
        print("Looking for system audio loopback options...")
        print("📋 Setup Instructions:")
        print("   Option 1: Enable Stereo Mix")
        print("   - Right-click sound icon → Recording devices")
        print("   - Enable 'Stereo Mix' if available")
        print("   Option 2: Install VB-Audio Virtual Cable")
        print("   - Download from: https://vb-audio.com/Cable/")
        return None

    elif system == "Linux":
        print("🐧 Linux System Audio Check")
        print("Looking for PulseAudio monitor sources...")
        try:
            result = subprocess.run(['pactl', 'list', 'sources'],
                                  capture_output=True, text=True, timeout=10)
            if 'monitor' in result.stdout.lower():
                print("✅ PulseAudio monitor sources found!")
                return True
            else:
                print("❌ No monitor sources found")
                print("📋 Setup Instructions:")
                print("   1. Ensure PulseAudio is running")
                print("   2. Check: pactl list sources")
                print("   3. Look for *.monitor sources")
                return False
        except:
            print("⚠️  Could not check PulseAudio automatically")
            return None
    else:
        print(f"❓ Unknown system: {system}")
        return None

def check_frontend_files():
    """Check if Sprint 3 implementation files exist"""
    files_to_check = [
        'frontend/src-tauri/src/audio/core.rs',
        'frontend/src-tauri/src/lib.rs',
        'frontend/src/app/page.tsx',
        'frontend/src/app/hud/page.tsx',
        'frontend/src/components/WhisperConnection.tsx'
    ]

    print("\n📁 Sprint 3 Implementation Files Check")
    all_exist = True

    for file in files_to_check:
        if os.path.exists(file):
            print(f"✅ {file}")
        else:
            print(f"❌ {file} - MISSING")
            all_exist = False

    return all_exist

def test_tauri_commands():
    """Check if Tauri commands are properly configured"""
    lib_rs_path = 'frontend/src-tauri/src/lib.rs'

    if not os.path.exists(lib_rs_path):
        print("❌ lib.rs not found")
        return False

    print("\n🔧 Tauri Commands Check")

    with open(lib_rs_path, 'r') as f:
        content = f.read()

    commands = [
        'start_native_audio_capture',
        'stop_native_audio_capture',
        'check_system_audio_device'
    ]

    all_commands_found = True
    for command in commands:
        if command in content:
            print(f"✅ {command}")
        else:
            print(f"❌ {command} - NOT FOUND")
            all_commands_found = False

    return all_commands_found

def main():
    print("🚀 Sprint 3 Native Audio Implementation Test")
    print("=" * 50)

    # Check system audio setup
    system_audio_ok = check_system_audio_setup()

    # Check Whisper backend
    print("\n🤖 Whisper Backend Check")
    whisper_ok = check_whisper_backend()
    if whisper_ok:
        print("✅ Whisper backend running on localhost:8080")
    else:
        print("❌ Whisper backend not running")
        print("📋 Start backend: Run Whisper server on port 8080")

    # Check implementation files
    files_ok = check_frontend_files()

    # Check Tauri commands
    commands_ok = test_tauri_commands()

    # Summary
    print("\n📊 Test Summary")
    print("=" * 30)

    if system_audio_ok:
        print("✅ System Audio: Ready")
    elif system_audio_ok is False:
        print("❌ System Audio: Setup Required")
    else:
        print("⚠️  System Audio: Manual Check Needed")

    print(f"{'✅' if whisper_ok else '❌'} Whisper Backend: {'Ready' if whisper_ok else 'Not Running'}")
    print(f"{'✅' if files_ok else '❌'} Implementation Files: {'Present' if files_ok else 'Missing'}")
    print(f"{'✅' if commands_ok else '❌'} Tauri Commands: {'Configured' if commands_ok else 'Missing'}")

    # Next steps
    print("\n🎯 Next Steps")
    print("=" * 20)

    if files_ok and commands_ok:
        print("1. 📁 cd frontend")
        print("2. 📦 npm install (if needed)")
        print("3. 🚀 npm run dev")
        print("4. 🎧 Test system audio capture in HUD")

        if not whisper_ok:
            print("5. ⚠️  Start Whisper backend first!")

        if system_audio_ok is False:
            print("6. ⚠️  Complete system audio setup first!")
    else:
        print("❌ Implementation incomplete - check missing files/commands")

    print(f"\n✨ Sprint 3 Status: {'🎯 READY FOR TESTING' if (files_ok and commands_ok) else '⚠️ SETUP REQUIRED'}")

if __name__ == "__main__":
    main()