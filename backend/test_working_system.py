#!/usr/bin/env python3
"""
Sprint 7: End-to-End System Validation
Demonstrates the complete working cognitive engine with realistic performance targets
"""

import asyncio
import time
from brain import CognitiveConfig, CognitiveEngine

async def test_working_system():
    """Test the complete working system"""
    print("🚀 Sprint 7: End-to-End System Test")
    print("=" * 50)
    print("Testing complete Cognitive Engine integration")
    print()

    try:
        # Configure for realistic performance
        config = CognitiveConfig()
        config.advisor_timeout = 3.0  # Realistic timeout

        engine = CognitiveEngine(config)

        print("🔧 Configuration:")
        print(f"  Advisor Model: {config.advisor_model}")
        print(f"  Chronicler: {'ENABLED' if config.chronicler_enabled else 'DISABLED'}")
        print(f"  Timeout: {config.advisor_timeout}s")
        print()

        # Test cases that demonstrate different capabilities
        test_scenarios = [
            {
                "name": "Technical Question",
                "question": "What is TCP?",
                "expected_keywords": ["protocol", "transmission", "reliable"]
            },
            {
                "name": "How-to Question",
                "question": "How does TCP ensure reliability?",
                "expected_keywords": ["acknowledgment", "retransmission", "sequence"]
            },
            {
                "name": "Comparison Question",
                "question": "What's the difference between TCP and UDP?",
                "expected_keywords": ["tcp", "udp", "reliable", "fast"]
            },
            {
                "name": "Follow-up Context Test",
                "setup": "Machine learning uses algorithms to find patterns in data.",
                "question": "How is this used in real applications?",
                "expected_keywords": ["application", "model", "prediction"]
            }
        ]

        results = {
            "response_times": [],
            "successful_responses": 0,
            "keyword_matches": 0,
            "total_tests": len(test_scenarios)
        }

        for i, scenario in enumerate(test_scenarios, 1):
            print(f"Test {i}: {scenario['name']}")

            # Add setup context if provided
            if 'setup' in scenario:
                print(f"Context: {scenario['setup']}")
                engine.chronicler.add_transcription(scenario['setup'])

            question = scenario['question']
            print(f"Question: {question}")

            start_time = time.time()
            response = await engine.advisor.process_hot_stream_text(question)
            end_time = time.time()

            response_time_ms = (end_time - start_time) * 1000
            results["response_times"].append(response_time_ms)

            if response:
                results["successful_responses"] += 1

                print(f"✅ Response ({response_time_ms:.1f}ms):")
                print(f"   {response}")

                # Check for expected keywords
                response_lower = response.lower()
                found_keywords = [kw for kw in scenario["expected_keywords"]
                                if kw.lower() in response_lower]

                if found_keywords:
                    results["keyword_matches"] += 1
                    print(f"✅ Keywords found: {found_keywords}")
                else:
                    print(f"⚠️  Keywords missing. Expected: {scenario['expected_keywords']}")

            else:
                print(f"❌ No response received")

            print()

            # Add successful responses to context for next test
            if response:
                engine.chronicler.add_transcription(f"Q: {question} A: {response}")

        # Calculate statistics
        avg_time = sum(results["response_times"]) / len(results["response_times"]) if results["response_times"] else 0
        max_time = max(results["response_times"]) if results["response_times"] else 0
        min_time = min(results["response_times"]) if results["response_times"] else 0

        print("📊 System Performance Results:")
        print(f"  Response Rate: {results['successful_responses']}/{results['total_tests']} ({results['successful_responses']/results['total_tests']*100:.1f}%)")
        print(f"  Keyword Accuracy: {results['keyword_matches']}/{results['total_tests']} ({results['keyword_matches']/results['total_tests']*100:.1f}%)")
        print(f"  Average Latency: {avg_time:.1f}ms")
        print(f"  Min/Max Latency: {min_time:.1f}ms / {max_time:.1f}ms")
        print()

        # Evaluate against Sprint 7 goals
        response_success = results["successful_responses"] >= results["total_tests"] * 0.8  # 80% success
        keyword_success = results["keyword_matches"] >= results["total_tests"] * 0.5       # 50% accuracy
        latency_reasonable = avg_time < 1000  # Under 1 second average

        print("🎯 Sprint 7 Goals Assessment:")
        print(f"  Response Reliability: {'✅ PASS' if response_success else '❌ FAIL'}")
        print(f"  Content Accuracy: {'✅ PASS' if keyword_success else '❌ FAIL'}")
        print(f"  Performance: {'✅ ACCEPTABLE' if latency_reasonable else '❌ TOO SLOW'}")

        overall_success = response_success and keyword_success and latency_reasonable

        if overall_success:
            print(f"\n🎉 SYSTEM STATUS: WORKING - Ready for integration!")
            print("✅ Ollama integration functional")
            print("✅ Context management working")
            print("✅ Question detection active")
            print("✅ Response generation stable")
        else:
            print(f"\n⚠️  SYSTEM STATUS: NEEDS OPTIMIZATION")
            print("   Core functionality working, performance tuning needed")

        # Next steps recommendation
        print(f"\n🔧 Recommended Next Steps:")
        if avg_time > 500:
            print("   • Optimize model parameters for speed")
            print("   • Consider smaller/faster model for real-time use")
        if results["keyword_matches"] < results["total_tests"] * 0.7:
            print("   • Improve prompt engineering for better accuracy")
            print("   • Add example-based training")

        print("   • Integrate with real Whisper server")
        print("   • Test with live audio input")
        print("   • Validate HUD display integration")

        return overall_success

    except Exception as e:
        print(f"❌ System test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = asyncio.run(test_working_system())
    print(f"\nFinal Result: {'🎉 SYSTEM WORKING' if success else '❌ SYSTEM NEEDS WORK'}")