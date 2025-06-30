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

  // Sprint 9: Use WebSocket hook instead of Tauri events
  const {
    isConnected,
    isPaused,
    lastMessage,
    lastTimestamp,
    connectionAttempts,
    sendPause,
    sendResume
  } = useAdvisorStream();

  // Sprint 9: Process advisor keywords from WebSocket
  useEffect(() => {
    if (lastMessage && lastTimestamp) {
      console.log('HUD: Received advisor keywords:', lastMessage);
      addTranscriptText(lastMessage, 0.9); // High confidence for advisor keywords
    }
  }, [lastMessage, lastTimestamp]);

  // Hotkey handling for pause/resume (Sprint 9 requirement)
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Check for Caps Lock key (keyCode 20) or can be configured for other keys
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
        return age < 10000; // Remove words older than 10 seconds
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
      }, index * 100);
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
      // Keep only last 20 words to prevent memory issues
      return updated.slice(-20);
    });
  };

  const getWordOpacity = (word: TranscriptWord) => {
    const age = Date.now() - word.timestamp;
    if (age < 1000) return 1; // Full opacity for first second
    if (age < 5000) return 0.8; // Fade to 80% for next 4 seconds
    if (age < 8000) return 0.5; // Fade to 50% for next 3 seconds
    return 0.3; // Very faded for oldest words
  };

  const getConfidenceColor = (confidence: number) => {
    if (confidence >= 0.8) return 'text-green-400';
    if (confidence >= 0.6) return 'text-yellow-400';
    if (confidence >= 0.4) return 'text-orange-400';
    return 'text-red-400';
  };

  // Sprint 9: Updated status logic for WebSocket connection
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
    <div className="w-full h-full bg-black bg-opacity-20 backdrop-blur-sm border border-gray-600 border-opacity-30 rounded-lg p-4 overflow-hidden">
      {/* Status Bar */}
      <div className="flex items-center justify-between mb-2 text-xs">
        <div className="flex items-center space-x-2">
          <div className={`w-2 h-2 rounded-full ${
            connectionStatus === 'connected' ? 'bg-green-500' :
            connectionStatus === 'error' ? 'bg-red-500' : 'bg-gray-500'
          }`} />
          <span className="text-gray-300">
            {getStatusText()}
          </span>
          {/* Sprint 9: Show connection attempts if reconnecting */}
          {connectionAttempts > 0 && !isConnected && (
            <span className="text-gray-500 text-xs">
              (attempt {connectionAttempts})
            </span>
          )}
        </div>
        <div className="text-gray-400">
          {words.length} words
        </div>
      </div>

      {/* Transcription Display */}
      <div className="flex flex-wrap gap-2 items-center min-h-[60px]">
        {words.length === 0 && (
          <div className="text-gray-400 text-center w-full">
            {isPaused ? 'System Paused - Press Caps Lock to resume' :
             isConnected ? 'Ready - Ask a question to see advisor keywords...' :
             'Connecting to Cognitive Engine...'}
          </div>
        )}

        {words.map((word, index) => (
          <span
            key={word.id}
            className={`
              text-lg font-medium transition-all duration-1000 ease-out
              ${getConfidenceColor(word.confidence)}
              animate-fade-in
            `}
            style={{
              opacity: getWordOpacity(word),
              transform: `translateY(${Math.max(0, (Date.now() - word.timestamp) / 100)}px)`
            }}
          >
            {word.word}
            {word.confidence < 0.6 && (
              <sup className="text-xs text-gray-500 ml-1">
                {Math.round(word.confidence * 100)}%
              </sup>
            )}
          </span>
        ))}
      </div>

      {/* Live Activity Indicator */}
      {isConnected && !isPaused && (
        <div className="absolute bottom-2 right-2">
          <div className="flex space-x-1">
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '0ms' }} />
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '200ms' }} />
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '400ms' }} />
          </div>
        </div>
      )}

      {/* Sprint 9: Pause indicator */}
      {isPaused && (
        <div className="absolute bottom-2 right-2">
          <div className="flex items-center space-x-2 text-orange-400 text-sm">
            <div className="w-2 h-4 bg-orange-400 rounded"></div>
            <div className="w-2 h-4 bg-orange-400 rounded"></div>
            <span className="text-xs">PAUSED</span>
          </div>
        </div>
      )}
    </div>
  );
}