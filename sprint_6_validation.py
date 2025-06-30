#!/usr/bin/env python3
"""
Sprint 6 Validation: "The Cognitive Engine"
Validates all implementations and tests Definition of Done criteria
"""

import asyncio
import time
import subprocess
import sys
from pathlib import Path
import json
import logging

class Sprint6Validator:
    def __init__(self):
        self.root_dir = Path.cwd()
        self.backend_dir = self.root_dir / "backend"
        self.brain_py = self.backend_dir / "brain.py"
        self.launch_script = self.backend_dir / "launch_cognitive_system.sh"
        self.test_script = self.backend_dir / "tests" / "test_latency.py"

        self.validation_results = {
            "cognitive_engine_implementation": {},
            "definition_of_done": {},
            "overall_readiness": False
        }

    def log_check(self, component: str, status: bool, details: str = ""):
        """Log validation check result"""
        symbol = "✅" if status else "❌"
        print(f"{symbol} {component}: {details}")
        return status

    def validate_cognitive_engine_implementation(self) -> bool:
        """Validate Sprint 6 cognitive engine implementation"""
        print("\n🧠 Validating Cognitive Engine Implementation...")

        checks = []

        # Check brain.py exists and has required components
        checks.append(self.log_check(
            "Cognitive Engine File",
            self.brain_py.exists(),
            "brain.py main orchestrator exists"
        ))

        if self.brain_py.exists():
            with open(self.brain_py, 'r') as f:
                content = f.read()

            # Check for core classes
            checks.append(self.log_check(
                "Chronicler Class",
                "class Chronicler:" in content,
                "Conversational memory system implemented"
            ))

            checks.append(self.log_check(
                "Advisor Class",
                "class Advisor:" in content,
                "Real-time assistance engine implemented"
            ))

            checks.append(self.log_check(
                "CognitiveEngine Class",
                "class CognitiveEngine:" in content,
                "Main orchestrator implemented"
            ))

            # Check for Sprint 6 specific features
            checks.append(self.log_check(
                "Question Detection Regex",
                "question_patterns" in content and "regex" in content,
                "Fast regex question detection"
            ))

            checks.append(self.log_check(
                "Context Store (deque)",
                "from collections import deque" in content and "deque(" in content,
                "Python deque for context management"
            ))

            checks.append(self.log_check(
                "700ms Timeout",
                "advisor_timeout: float = 0.7" in content,
                "700ms response time limit configured"
            ))

            checks.append(self.log_check(
                "Async/Await Implementation",
                "async def" in content and "await" in content,
                "Async architecture for concurrency"
            ))

        # Check launch script
        checks.append(self.log_check(
            "Launch Script",
            self.launch_script.exists(),
            "Complete system launch configuration"
        ))

        if self.launch_script.exists():
            with open(self.launch_script, 'r') as f:
                launch_content = f.read()

            checks.append(self.log_check(
                "GPU Resource Management",
                "GPU_LAYERS_WHISPER" in launch_content and "GPU_LAYERS_OLLAMA" in launch_content,
                "Separate GPU layer limits for dual models"
            ))

            checks.append(self.log_check(
                "Model Configuration",
                "llama3:8b-instruct-q4_k_m" in launch_content and "phi3:mini-instruct-q4" in launch_content,
                "Correct models for Advisor and Chronicler"
            ))

        self.validation_results["cognitive_engine_implementation"]["core_implementation"] = all(checks)
        return all(checks)

    def validate_chronicler_implementation(self) -> bool:
        """Validate Chronicler (conversational memory) implementation"""
        print("\n📚 Validating Chronicler Implementation...")

        checks = []

        if self.brain_py.exists():
            with open(self.brain_py, 'r') as f:
                content = f.read()

            # Check Chronicler features
            checks.append(self.log_check(
                "Context Store",
                "context_store = deque(maxlen=" in content,
                "Fixed-size context store with deque"
            ))

            checks.append(self.log_check(
                "Summarization Timer",
                "summarization_timer" in content,
                "5-second summarization trigger"
            ))

            checks.append(self.log_check(
                "Cold Path Subscription",
                "/inference" in content,
                "Subscribes to high-accuracy cold path"
            ))

            checks.append(self.log_check(
                "Context Dictionary",
                "get_context_dict" in content,
                "Context payload for Advisor prompts"
            ))

            checks.append(self.log_check(
                "Debug Context Ticker",
                "debug_print_context" in content,
                "Context ticker for monitoring"
            ))

        self.validation_results["cognitive_engine_implementation"]["chronicler"] = all(checks)
        return all(checks)

    def validate_advisor_implementation(self) -> bool:
        """Validate Advisor (real-time assistance) implementation"""
        print("\n🎯 Validating Advisor Implementation...")

        checks = []

        if self.brain_py.exists():
            with open(self.brain_py, 'r') as f:
                content = f.read()

            # Check Advisor features
            checks.append(self.log_check(
                "Question Detection",
                "is_question" in content and "question_regex" in content,
                "Fast regex question detection"
            ))

            checks.append(self.log_check(
                "Hot Stream Processing",
                "process_hot_stream_text" in content,
                "Real-time hot stream processing"
            ))

            checks.append(self.log_check(
                "Response Time Tracking",
                "last_response_time" in content,
                "Response time measurement"
            ))

            checks.append(self.log_check(
                "Bullet Point Format",
                "•" in content,
                "Bullet point response format for HUD"
            ))

            checks.append(self.log_check(
                "Timeout Protection",
                "asyncio.wait_for" in content and "timeout=" in content,
                "700ms timeout protection"
            ))

        self.validation_results["cognitive_engine_implementation"]["advisor"] = all(checks)
        return all(checks)

    async def test_context_ticker(self) -> bool:
        """Test Definition of Done: Context Ticker Works"""
        print("\n⏰ Testing Context Ticker...")

        try:
            # Import and test basic functionality
            sys.path.insert(0, str(self.backend_dir))
            from brain import CognitiveConfig, CognitiveEngine

            config = CognitiveConfig()
            engine = CognitiveEngine(config)

            # Test context debugging
            engine.chronicler.add_transcription("Test transcription for context ticker.")
            engine.chronicler.debug_print_context()

            return self.log_check(
                "Context Ticker",
                len(engine.chronicler.context_store) > 0,
                "Context store receives and displays transcriptions"
            )

        except Exception as e:
            return self.log_check(
                "Context Ticker",
                False,
                f"Error testing context ticker: {e}"
            )

    async def test_contextual_qa(self) -> bool:
        """Test Definition of Done: Contextual Q&A Passes"""
        print("\n❓ Testing Contextual Q&A...")

        try:
            from brain import CognitiveConfig, CognitiveEngine

            config = CognitiveConfig()
            engine = CognitiveEngine(config)

            # Set up context
            engine.chronicler.add_transcription("We are discussing TCP protocols.")
            engine.chronicler.add_transcription("TCP is a reliable transport protocol.")

            # Test two-part question scenario
            response1 = await engine.advisor.process_hot_stream_text("What is TCP?")
            response2 = await engine.advisor.process_hot_stream_text("And which one is faster?")

            success = (response1 is not None and response2 is not None and
                      len(response1) > 0 and len(response2) > 0)

            return self.log_check(
                "Contextual Q&A",
                success,
                f"Two-part Q&A: '{response1}' → '{response2}'"
            )

        except Exception as e:
            return self.log_check(
                "Contextual Q&A",
                False,
                f"Error testing contextual Q&A: {e}"
            )

    async def test_latency_gate(self) -> bool:
        """Test Definition of Done: CI Latency Gate Passes"""
        print("\n🚀 Testing CI Latency Gate...")

        try:
            # Run the latency test
            if self.test_script.exists():
                result = subprocess.run([
                    sys.executable, str(self.test_script)
                ], capture_output=True, text=True, cwd=self.backend_dir)

                success = result.returncode == 0
                output = result.stdout if success else result.stderr

                return self.log_check(
                    "CI Latency Gate",
                    success,
                    f"Max advisor response time < 700ms: {success}"
                )
            else:
                return self.log_check(
                    "CI Latency Gate",
                    False,
                    "Test script not found"
                )

        except Exception as e:
            return self.log_check(
                "CI Latency Gate",
                False,
                f"Error running latency test: {e}"
            )

    def test_launch_configuration(self) -> bool:
        """Test Definition of Done: Launch Configuration"""
        print("\n🚀 Testing Launch Configuration...")

        checks = []

        # Check launch script executable
        checks.append(self.log_check(
            "Launch Script Executable",
            self.launch_script.exists() and os.access(self.launch_script, os.X_OK),
            "launch_cognitive_system.sh is executable"
        ))

        # Check dependency validation
        if self.launch_script.exists():
            with open(self.launch_script, 'r') as f:
                content = f.read()

            checks.append(self.log_check(
                "Dependency Checking",
                "check_dependencies" in content,
                "Validates Whisper, Ollama, and models"
            ))

            checks.append(self.log_check(
                "GPU Configuration",
                "CUDA_VISIBLE_DEVICES" in content,
                "Proper GPU resource allocation"
            ))

            checks.append(self.log_check(
                "Health Monitoring",
                "monitor_system" in content,
                "System health monitoring"
            ))

            checks.append(self.log_check(
                "Graceful Cleanup",
                "cleanup" in content and "trap cleanup EXIT" in content,
                "Proper process cleanup on exit"
            ))

        self.validation_results["definition_of_done"]["launch_configuration"] = all(checks)
        return all(checks)

    async def run_definition_of_done_tests(self) -> bool:
        """Run all Definition of Done tests"""
        print("\n🎯 Running Definition of Done Tests...")

        # Test 1: Context Ticker Works
        ticker_ok = await self.test_context_ticker()

        # Test 2: Contextual Q&A Passes
        qa_ok = await self.test_contextual_qa()

        # Test 3: CI Latency Gate Passes
        latency_ok = await self.test_latency_gate()

        # Test 4: Launch Configuration Works
        launch_ok = self.test_launch_configuration()

        # Store results
        self.validation_results["definition_of_done"] = {
            "context_ticker": ticker_ok,
            "contextual_qa": qa_ok,
            "ci_latency_gate": latency_ok,
            "launch_configuration": launch_ok
        }

        return all([ticker_ok, qa_ok, latency_ok, launch_ok])

    def generate_next_steps(self) -> list:
        """Generate next steps based on validation results"""
        next_steps = []

        if not self.validation_results["cognitive_engine_implementation"].get("core_implementation", False):
            next_steps.append("🔧 Complete cognitive engine core implementation")

        if not self.validation_results["cognitive_engine_implementation"].get("chronicler", False):
            next_steps.append("📚 Implement Chronicler conversational memory")

        if not self.validation_results["cognitive_engine_implementation"].get("advisor", False):
            next_steps.append("🎯 Implement Advisor real-time assistance")

        if not self.validation_results["definition_of_done"].get("context_ticker", False):
            next_steps.append("⏰ Fix context ticker implementation")

        if not self.validation_results["definition_of_done"].get("contextual_qa", False):
            next_steps.append("❓ Debug contextual Q&A functionality")

        if not self.validation_results["definition_of_done"].get("ci_latency_gate", False):
            next_steps.append("🚀 Optimize advisor response time to <700ms")

        if not self.validation_results["definition_of_done"].get("launch_configuration", False):
            next_steps.append("🚀 Complete launch script configuration")

        # Always recommend these deployment steps
        next_steps.extend([
            "📦 Install Ollama and download required models",
            "🏗️ Build Whisper server with Sprint 5 optimizations",
            "🧪 Run complete system with launch_cognitive_system.sh",
            "🎯 Validate <700ms response time on target hardware"
        ])

        return next_steps

    async def run_full_validation(self) -> dict:
        """Run complete Sprint 6 validation"""
        print("🧠 Sprint 6: 'The Cognitive Engine' - Validation Report")
        print("=" * 60)

        # Implementation validation
        print("\n📍 COGNITIVE ENGINE IMPLEMENTATION")
        core_ok = self.validate_cognitive_engine_implementation()
        chronicler_ok = self.validate_chronicler_implementation()
        advisor_ok = self.validate_advisor_implementation()

        implementation_complete = all([core_ok, chronicler_ok, advisor_ok])

        # Definition of Done tests
        print("\n📍 DEFINITION OF DONE TESTS")
        dod_ok = await self.run_definition_of_done_tests()

        # Overall assessment
        self.validation_results["overall_readiness"] = implementation_complete and dod_ok

        print(f"\n📋 SPRINT 6 VALIDATION SUMMARY")
        print("=" * 40)
        print(f"✅ Implementation Complete: {'YES' if implementation_complete else 'NO'}")
        print(f"✅ Definition of Done: {'PASSED' if dod_ok else 'PENDING'}")
        print(f"✅ Overall Readiness: {'READY' if self.validation_results['overall_readiness'] else 'IN PROGRESS'}")

        # Next steps
        next_steps = self.generate_next_steps()
        if next_steps:
            print(f"\n🎯 NEXT STEPS:")
            for step in next_steps:
                print(f"   {step}")

        print(f"\n🎉 Sprint 6 implementation is {'COMPLETE' if self.validation_results['overall_readiness'] else 'IN PROGRESS'}!")

        return {
            "validation_results": self.validation_results,
            "next_steps": next_steps,
            "ready_for_deployment": self.validation_results["overall_readiness"]
        }

async def main():
    validator = Sprint6Validator()
    results = await validator.run_full_validation()

    # Save results
    with open('sprint_6_validation_results.json', 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n📁 Validation results saved to: sprint_6_validation_results.json")

    return 0 if results["ready_for_deployment"] else 1

if __name__ == "__main__":
    import os
    exit(asyncio.run(main()))