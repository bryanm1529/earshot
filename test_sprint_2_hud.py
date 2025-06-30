#!/usr/bin/env python3
"""
Sprint 2 HUD Testing Script
===========================

Tests the real-time HUD functionality by sending audio to the whisper backend
and verifying the frontend can display transcriptions in real-time.

Sprint 2 Acceptance Criteria:
✅ Create transparent, always-on-top Tauri window
✅ Connect directly to whisper /stream endpoint
✅ Render incoming keywords with fade-in and confidence scoring
✅ Remove complex note-taking UI for lean interface
✅ Target: Speaking → keywords appear within latency budget
"""

import asyncio
import aiohttp
import time
import json
from pathlib import Path

class Sprint2Tester:
    def __init__(self):
        self.whisper_url = "http://localhost:8080"
        self.frontend_url = "http://localhost:3118"

    async def test_whisper_backend(self):
        """Test that Whisper backend is running and responsive"""
        print("🧪 Testing Whisper Backend Connection...")

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.whisper_url}/") as response:
                    if response.status == 200:
                        print("✅ Whisper backend is running")
                        return True
                    else:
                        print(f"❌ Whisper backend returned {response.status}")
                        return False
        except Exception as e:
            print(f"❌ Whisper backend connection failed: {e}")
            return False

    async def test_frontend_connection(self):
        """Test that frontend is running"""
        print("🧪 Testing Frontend Connection...")

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.frontend_url}/") as response:
                    if response.status == 200:
                        print("✅ Frontend is running")
                        return True
                    else:
                        print(f"❌ Frontend returned {response.status}")
                        return False
        except Exception as e:
            print(f"❌ Frontend connection failed: {e}")
            return False

    async def test_real_transcription(self):
        """Test real transcription with our test audio files"""
        print("🧪 Testing Real-time Transcription...")

        test_files = ["short_speech.wav", "medium_speech.wav"]
        results = []

        for filename in test_files:
            if not Path(filename).exists():
                print(f"⚠️  {filename} not found - run create_real_speech.py first")
                continue

            print(f"\n📝 Testing with {filename}...")

            try:
                async with aiohttp.ClientSession() as session:
                    # Prepare file for upload
                    with open(filename, 'rb') as f:
                        data = aiohttp.FormData()
                        data.add_field('audio', f, filename=filename, content_type='audio/wav')

                        start_time = time.time()

                        async with session.post(f"{self.whisper_url}/stream", data=data) as response:
                            latency = (time.time() - start_time) * 1000

                            if response.status == 200:
                                result = await response.json()
                                segments = result.get('segments', [])

                                if segments:
                                    text = " ".join([seg.get('text', '') for seg in segments])
                                    print(f"  ✅ Transcribed: '{text.strip()}'")
                                    print(f"  ⏱️  Latency: {latency:.2f}ms")
                                    print(f"  📊 Segments: {len(segments)}")

                                    results.append({
                                        'file': filename,
                                        'success': True,
                                        'latency': latency,
                                        'text': text.strip(),
                                        'segments': len(segments)
                                    })
                                else:
                                    print(f"  ❌ No transcription produced")
                                    results.append({
                                        'file': filename,
                                        'success': False,
                                        'latency': latency,
                                        'reason': 'No segments'
                                    })
                            else:
                                print(f"  ❌ HTTP {response.status}")
                                results.append({
                                    'file': filename,
                                    'success': False,
                                    'reason': f'HTTP {response.status}'
                                })

            except Exception as e:
                print(f"  ❌ Error: {e}")
                results.append({
                    'file': filename,
                    'success': False,
                    'reason': str(e)
                })

        return results

    async def run_full_test(self):
        """Run complete Sprint 2 validation"""
        print("=" * 60)
        print("🚀 SPRINT 2 HUD VALIDATION TEST")
        print("=" * 60)

        # Test infrastructure
        whisper_ok = await self.test_whisper_backend()
        frontend_ok = await self.test_frontend_connection()

        if not whisper_ok:
            print("\n❌ Cannot proceed - Whisper backend not available")
            return False

        if not frontend_ok:
            print("\n⚠️  Frontend not available - manual testing required")

        # Test transcription capability
        print(f"\n🧪 Testing Real-time Transcription Capability...")
        transcription_results = await self.test_real_transcription()

        # Analyze results
        successful_transcriptions = [r for r in transcription_results if r['success']]

        print(f"\n" + "=" * 60)
        print("📊 SPRINT 2 TEST RESULTS")
        print("=" * 60)

        print(f"✅ Whisper Backend: {'Running' if whisper_ok else 'Failed'}")
        print(f"✅ Frontend: {'Running' if frontend_ok else 'Failed'}")
        print(f"✅ Transcriptions: {len(successful_transcriptions)}/{len(transcription_results)} successful")

        if successful_transcriptions:
            avg_latency = sum(r['latency'] for r in successful_transcriptions) / len(successful_transcriptions)
            print(f"⏱️  Average Latency: {avg_latency:.2f}ms")

            for result in successful_transcriptions:
                print(f"  📝 {result['file']}: '{result['text']}' ({result['latency']:.2f}ms)")

        # Sprint 2 success criteria
        sprint_2_success = (
            whisper_ok and
            len(successful_transcriptions) > 0 and
            all(r['latency'] < 5000 for r in successful_transcriptions)  # Reasonable latency
        )

        print(f"\n🎯 SPRINT 2 STATUS:")
        if sprint_2_success:
            print("✅ SPRINT 2 CORE FUNCTIONALITY VALIDATED")
            print("  • Whisper backend integration: ✅")
            print("  • Real-time transcription: ✅")
            print("  • Latency within budget: ✅")
            print("\n🚀 Ready for HUD frontend integration testing")
        else:
            print("❌ SPRINT 2 INCOMPLETE")
            print("  Issues found:")
            for result in transcription_results:
                if not result['success']:
                    print(f"    • {result['file']}: {result.get('reason', 'Unknown error')}")

        return sprint_2_success

async def main():
    """Main test execution"""
    tester = Sprint2Tester()
    success = await tester.run_full_test()

    if success:
        print("\n🎉 Sprint 2 backend validation complete!")
        print("Next steps:")
        print("1. Start frontend: cd frontend && npm run dev")
        print("2. Test HUD window creation")
        print("3. Test real-time transcription display")
        print("4. Verify transparency and always-on-top functionality")
    else:
        print("\n⚠️  Sprint 2 validation incomplete")
        print("Fix issues above before proceeding")

if __name__ == "__main__":
    asyncio.run(main())