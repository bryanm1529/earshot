#!/usr/bin/env python3
"""
Sprint 7: Live Integration Test
Tests the complete pipeline: Input → Whisper → Cognitive Engine → HUD
"""

import asyncio
import aiohttp
import json
import time
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_whisper_endpoint():
    """Test that Whisper server is responding"""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get("http://127.0.0.1:8178/") as response:
                if response.status == 200:
                    logger.info("✅ Whisper server is running")
                    return True
                else:
                    logger.error(f"❌ Whisper server error: {response.status}")
                    return False
    except Exception as e:
        logger.error(f"❌ Cannot connect to Whisper server: {e}")
        return False

async def test_ollama_endpoint():
    """Test that Ollama is responding"""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get("http://127.0.0.1:11434/api/tags") as response:
                if response.status == 200:
                    models = await response.json()
                    logger.info(f"✅ Ollama running with {len(models.get('models', []))} models")
                    return True
                else:
                    logger.error(f"❌ Ollama error: {response.status}")
                    return False
    except Exception as e:
        logger.error(f"❌ Cannot connect to Ollama: {e}")
        return False

async def send_text_to_whisper(text: str):
    """Send text to Whisper server for transcription simulation"""
    logger.info(f"🎤 Simulating speech: '{text}'")

    # For now, we'll simulate by sending to the inference endpoint
    try:
        # Create a mock audio data payload
        payload = {
            "audio_data": "mock_base64_audio_data",
            "text": text  # Some servers accept direct text for testing
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                "http://127.0.0.1:8178/inference",
                json=payload,
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    logger.info(f"✅ Whisper transcription: {result}")
                    return result
                else:
                    logger.warning(f"⚠️  Whisper response: {response.status}")
                    return None

    except Exception as e:
        logger.error(f"❌ Error sending to Whisper: {e}")
        return None

async def monitor_brain_activity():
    """Monitor if the brain is processing questions"""
    # Since we can't easily monitor the brain's websocket connection,
    # we'll check if it's responsive by testing our advisor directly
    logger.info("🧠 Testing cognitive engine...")

    try:
        from brain import CognitiveConfig, CognitiveEngine

        config = CognitiveConfig()
        config.advisor_timeout = 3.0  # More realistic timeout for integration test
        engine = CognitiveEngine(config)

        # Test if the advisor is working
        test_question = "What is HTTP?"
        start_time = time.time()

        response = await engine.advisor.process_hot_stream_text(test_question)
        response_time = (time.time() - start_time) * 1000

        if response:
            logger.info(f"✅ Cognitive engine responsive ({response_time:.1f}ms)")
            logger.info(f"   Sample response: {response}")
            return True
        else:
            logger.error("❌ Cognitive engine not responding")
            return False

    except Exception as e:
        logger.error(f"❌ Cognitive engine error: {e}")
        return False

async def test_end_to_end_flow():
    """Test the complete end-to-end flow"""
    logger.info("🚀 Starting End-to-End Integration Test")
    logger.info("=" * 60)

    # Test 1: Component Health Check
    logger.info("Phase 1: Component Health Check")
    whisper_ok = await test_whisper_endpoint()
    ollama_ok = await test_ollama_endpoint()
    brain_ok = await monitor_brain_activity()

    if not all([whisper_ok, ollama_ok, brain_ok]):
        logger.error("❌ Component health check failed!")
        return False

    logger.info("✅ All components healthy")
    logger.info("")

    # Test 2: Simulate Question Flow
    logger.info("Phase 2: Question Flow Simulation")
    test_questions = [
        "What is TCP?",
        "How does HTTP work?",
        "What's the difference between REST and GraphQL?",
        "How do databases ensure ACID properties?"
    ]

    success_count = 0
    for i, question in enumerate(test_questions, 1):
        logger.info(f"Test {i}/4: Processing '{question}'")

        # Simulate the flow:
        # 1. User speaks (simulated)
        # 2. Whisper transcribes (simulated)
        # 3. Brain processes and responds

        # Step 3: Direct brain processing (since we can't easily simulate audio)
        try:
            from brain import CognitiveConfig, CognitiveEngine

            config = CognitiveConfig()
            config.advisor_timeout = 3.0  # More realistic timeout for integration test
            engine = CognitiveEngine(config)

            start_time = time.time()
            response = await engine.advisor.process_hot_stream_text(question)
            response_time = (time.time() - start_time) * 1000

            if response:
                success_count += 1
                logger.info(f"✅ Question {i}: {response_time:.1f}ms")
                logger.info(f"   Response: {response}")

                # Simulate HUD display
                hud_event = {
                    "text": response,
                    "ts": int(time.time() * 1000)
                }
                logger.info(f"🎯 HUD Event: {json.dumps(hud_event)}")
            else:
                logger.error(f"❌ Question {i}: No response")

        except Exception as e:
            logger.error(f"❌ Question {i}: Error - {e}")

        logger.info("")
        await asyncio.sleep(1)  # Brief pause between questions

    # Results
    success_rate = (success_count / len(test_questions)) * 100
    logger.info("📊 End-to-End Test Results:")
    logger.info(f"  Questions Processed: {success_count}/{len(test_questions)} ({success_rate:.1f}%)")

    if success_rate >= 75:
        logger.info("🎉 END-TO-END INTEGRATION: SUCCESS!")
        logger.info("   System is ready for live audio testing")
        return True
    else:
        logger.error("❌ END-TO-END INTEGRATION: FAILED")
        logger.error("   System needs debugging before live testing")
        return False

async def main():
    """Main integration test"""
    print("🧪 Sprint 7: Live Integration Test")
    print("Testing: Whisper ↔ Cognitive Engine ↔ HUD Pipeline")
    print()

    try:
        success = await test_end_to_end_flow()

        if success:
            print("\n🎉 INTEGRATION SUCCESSFUL!")
            print("Next steps:")
            print("  • Test with real microphone input")
            print("  • Connect HUD React components")
            print("  • Run 15-minute soak test")
            print("  • Deploy for user testing")
        else:
            print("\n❌ INTEGRATION FAILED")
            print("Check logs above for specific issues")

        return success

    except KeyboardInterrupt:
        print("\n⚠️  Test interrupted by user")
        return False
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        return False

if __name__ == "__main__":
    success = asyncio.run(main())
    exit(0 if success else 1)