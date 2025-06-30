'use client';

import { useState, useEffect, useRef } from 'react';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';

interface TranscriptWord {
  id: string;
  word: string;
  confidence: number;
  timestamp: number;
  fadeStartTime?: number;
}

interface TranscriptUpdate {
  text: string;
  timestamp: string;
  source: string;
}

export default function HUD() {
  const [words, setWords] = useState<TranscriptWord[]>([]);
  const [isActive, setIsActive] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState<'disconnected' | 'connected' | 'error'>('disconnected');
  const wordCounterRef = useRef(0);

  useEffect(() => {
    const currentWindow = getCurrentWindow();

    // Listen for control messages from main window and native audio events
    const setupEventListeners = async () => {
      // Listen for start/stop transcription events from main window
      const unlisten1 = await listen('start-transcription', () => {
        console.log('HUD: Start transcription received');
        setIsActive(true);
        setConnectionStatus('connected');
      });

      const unlisten2 = await listen('stop-transcription', () => {
        console.log('HUD: Stop transcription received');
        setIsActive(false);
        setConnectionStatus('disconnected');
      });

      // Listen for native transcript updates from Rust backend
      const unlisten3 = await listen('hud-transcript-update', (event: any) => {
        console.log('HUD: Received native transcript update:', event.payload);
        const update = event.payload as TranscriptUpdate;
        if (update && update.text) {
          addTranscriptText(update.text, 0.8); // Default confidence for native transcripts
        }
      });

      // Listen for status updates from native audio capture
      const unlisten4 = await listen('hud-status', (event: any) => {
        console.log('HUD: Received status update:', event.payload);
        const status = event.payload as string;
        if (status === 'connected') {
          setConnectionStatus('connected');
          setIsActive(true);
        } else if (status === 'disconnected') {
          setConnectionStatus('disconnected');
          setIsActive(false);
        }
      });

      // Listen for errors from native audio capture
      const unlisten5 = await listen('hud-error', (event: any) => {
        console.error('HUD: Received error from native audio:', event.payload);
        setConnectionStatus('error');
        // You could also show error messages in the HUD if desired
      });

      return () => {
        unlisten1();
        unlisten2();
        unlisten3();
        unlisten4();
        unlisten5();
      };
    };

    setupEventListeners();

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
            {isActive ? 'System Audio Active' : 'Standby'}
          </span>
        </div>
        <div className="text-gray-400">
          {words.length} words
        </div>
      </div>

      {/* Transcription Display */}
      <div className="flex flex-wrap gap-2 items-center min-h-[60px]">
        {words.length === 0 && (
          <div className="text-gray-400 text-center w-full">
            {isActive ? 'Listening to system audio...' : 'HUD Ready - Click "Start Recording" to begin'}
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
      {isActive && (
        <div className="absolute bottom-2 right-2">
          <div className="flex space-x-1">
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '0ms' }} />
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '200ms' }} />
            <div className="w-1 h-4 bg-blue-500 rounded animate-pulse" style={{ animationDelay: '400ms' }} />
          </div>
        </div>
      )}
    </div>
  );
}