'use client';

import { useState, useEffect, useRef } from 'react';
import { useAdvisorStream } from '../../hooks/useAdvisorStream';

interface TranscriptWord {
  id: string;
  word: string;
  confidence: number;
  timestamp: number;
  fadeStartTime?: number;
}

export default function HUD() {
  const [words, setWords] = useState<TranscriptWord[]>([]);
  const wordCounterRef = useRef(0);

  // Use WebSocket hook for advisor stream
  const {
    isConnected,
    isPaused,
    lastMessage,
    lastTimestamp,
    connectionAttempts,
    sendPause,
    sendResume
  } = useAdvisorStream();

  // Process advisor keywords from WebSocket
  useEffect(() => {
    if (lastMessage && lastTimestamp) {
      console.log('HUD: Received advisor keywords:', lastMessage);
      addTranscriptText(lastMessage, 0.9); // High confidence for advisor keywords
    }
  }, [lastMessage, lastTimestamp]);

  // Hotkey handling for pause/resume
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Caps Lock key
      if (event.code === 'CapsLock') {
        event.preventDefault();
        if (isPaused) {
          sendResume();
          console.log('HUD: System resumed via hotkey');
        } else {
          sendPause();
          console.log('HUD: System paused via hotkey');
        }
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isPaused, sendPause, sendResume]);

  useEffect(() => {
    // Auto-fade old words
    const fadeInterval = setInterval(() => {
      const now = Date.now();
      setWords(prev => prev.filter(word => {
        const age = now - word.timestamp;
        return age < 12000; // Remove words older than 12 seconds
      }));
    }, 1000);

    return () => {
      clearInterval(fadeInterval);
    };
  }, []);

  const addTranscriptText = (text: string, confidence: number) => {
    console.log('HUD: Adding transcript text:', text);

    // Split text into words and add each word
    const words = text.trim().split(/\s+/).filter(word => word.length > 0);

    words.forEach((word, index) => {
      // Add small delay between words for a more natural appearance
      setTimeout(() => {
        addWord(word, confidence);
      }, index * 150);
    });
  };

  const addWord = (word: string, confidence: number) => {
    const newWord: TranscriptWord = {
      id: `word-${wordCounterRef.current++}`,
      word,
      confidence,
      timestamp: Date.now()
    };

    setWords(prev => {
      const updated = [...prev, newWord];
      // Keep only last 15 words to prevent overcrowding
      return updated.slice(-15);
    });
  };

  const getWordOpacity = (word: TranscriptWord) => {
    const age = Date.now() - word.timestamp;
    if (age < 1000) return 1; // Full opacity for first second
    if (age < 4000) return 0.9; // Slight fade for next 3 seconds
    if (age < 8000) return 0.6; // More fade for next 4 seconds
    return 0.3; // Very faded for oldest words
  };

  const getWordScale = (word: TranscriptWord) => {
    const age = Date.now() - word.timestamp;
    if (age < 500) return 'scale-110'; // Slightly larger when new
    return 'scale-100';
  };

  const getConfidenceStyle = (confidence: number) => {
    if (confidence >= 0.8) return 'text-white shadow-lg shadow-white/20';
    if (confidence >= 0.6) return 'text-yellow-300 shadow-lg shadow-yellow-300/20';
    if (confidence >= 0.4) return 'text-orange-300 shadow-lg shadow-orange-300/20';
    return 'text-red-300 shadow-lg shadow-red-300/20';
  };

  // Connection status logic
  const getConnectionStatus = () => {
    if (!isConnected && connectionAttempts > 0) return 'error';
    if (isConnected) return 'connected';
    return 'disconnected';
  };

  const getStatusText = () => {
    if (isPaused) return 'System Paused';
    if (!isConnected) return connectionAttempts > 0 ? 'Reconnecting...' : 'Connecting...';
    return 'Advisor Active';
  };

  const connectionStatus = getConnectionStatus();

  return (
    <div className="w-full h-full relative">
      {/* Main HUD Container */}
      <div className="w-full h-full glass-card overflow-hidden shadow-2xl">
        {/* Subtle gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-br from-white/5 via-transparent to-black/10 pointer-events-none" />

        {/* Status Bar */}
        <div className="relative z-10 flex items-center justify-between px-6 py-3 border-b border-white/10 bg-white/5">
          <div className="flex items-center space-x-3">
            <div className={`w-2.5 h-2.5 rounded-full transition-all duration-500 ${
              connectionStatus === 'connected' ? 'bg-green-400 shadow-lg shadow-green-400/50 animate-glow' :
              connectionStatus === 'error' ? 'bg-red-400 shadow-lg shadow-red-400/50 animate-pulse' :
              'bg-gray-400 shadow-lg shadow-gray-400/50'
            }`} />
            <span className="text-primary text-sm font-medium tracking-wide">
              {getStatusText()}
            </span>
            {/* Connection attempts indicator */}
            {connectionAttempts > 0 && !isConnected && (
              <span className="text-tertiary text-xs font-mono">
                #{connectionAttempts}
              </span>
            )}
          </div>

          <div className="flex items-center space-x-4">
            <div className="text-secondary text-xs font-mono">
              {words.length} words
            </div>
            {/* Live indicator */}
            {isConnected && !isPaused && (
              <div className="flex items-center space-x-1">
                <div className="w-1.5 h-1.5 bg-blue-400 rounded-full animate-pulse" />
                <span className="text-blue-400 text-xs font-medium">LIVE</span>
              </div>
            )}
          </div>
        </div>

        {/* Transcription Display */}
        <div className="relative z-10 p-6 min-h-[80px] flex items-center">
          {words.length === 0 ? (
            <div className="w-full text-center">
              <div className="text-secondary text-lg font-light">
                {isPaused ? (
                  <div className="flex items-center justify-center space-x-3">
                    <div className="w-3 h-6 bg-orange-400 rounded-sm animate-pulse" />
                    <span>System Paused</span>
                    <div className="w-3 h-6 bg-orange-400 rounded-sm animate-pulse" />
                  </div>
                ) : isConnected ? (
                  <div className="flex items-center justify-center space-x-2">
                    <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                    <span>Ready for AI assistance...</span>
                    <div className="w-2 h-2 bg-blue-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                  </div>
                ) : (
                  <div className="flex items-center justify-center space-x-2">
                    <div className="w-2 h-2 bg-gray-400 rounded-full animate-pulse" />
                    <span>Connecting to Cognitive Engine...</span>
                  </div>
                )}
              </div>
              <div className="mt-3 text-tertiary text-sm">
                Press <kbd className="px-2 py-1 bg-white/10 rounded text-xs font-mono">Caps Lock</kbd> to pause/resume
              </div>
            </div>
          ) : (
            <div className="flex flex-wrap gap-3 items-center justify-center w-full">
              {words.map((word, index) => (
                <span
                  key={word.id}
                  className={`
                    text-xl font-medium transition-all duration-700 ease-out transform
                    ${getConfidenceStyle(word.confidence)}
                    ${getWordScale(word)}
                    animate-slide-in-up
                  `}
                  style={{
                    opacity: getWordOpacity(word),
                    animationDelay: `${index * 100}ms`,
                    textShadow: '0 0 20px rgba(255, 255, 255, 0.3)'
                  }}
                >
                  {word.word}
                  {word.confidence < 0.7 && (
                    <sup className="text-xs text-tertiary ml-1 font-mono">
                      {Math.round(word.confidence * 100)}%
                    </sup>
                  )}
                </span>
              ))}
            </div>
          )}
        </div>

        {/* Bottom indicators */}
        <div className="absolute bottom-4 left-6 right-6 flex justify-between items-center">
          {/* Activity indicator */}
          {isConnected && !isPaused && (
            <div className="flex items-center space-x-2">
              <div className="flex space-x-1">
                <div className="w-1 h-6 bg-gradient-to-t from-blue-500 to-purple-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
                <div className="w-1 h-4 bg-gradient-to-t from-blue-500 to-purple-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
                <div className="w-1 h-5 bg-gradient-to-t from-blue-500 to-purple-500 rounded-full animate-pulse" style={{ animationDelay: '400ms' }} />
              </div>
              <span className="text-tertiary text-xs font-medium">Processing</span>
            </div>
          )}

          {/* Pause indicator */}
          {isPaused && (
            <div className="flex items-center space-x-3 text-orange-400">
              <div className="flex space-x-1">
                <div className="w-2 h-6 bg-orange-400 rounded-sm" />
                <div className="w-2 h-6 bg-orange-400 rounded-sm" />
              </div>
              <span className="text-sm font-medium">PAUSED</span>
            </div>
          )}

          {/* Branding */}
          <div className="text-tertiary text-xs font-light tracking-wide">
            Earshot Copilot
          </div>
        </div>
      </div>
    </div>
  );
}