'use client';

import { useEffect, useState, useRef } from 'react';
import { Mic, MicOff, Wifi, WifiOff } from 'lucide-react';

interface RecordingControlsProps {
  isRecording: boolean;
  barHeights: string[];
  onRecordingStop: () => void;
  onRecordingStart: () => void;
  onTranscriptReceived?: (summary: any) => void;
}

export const RecordingControls: React.FC<RecordingControlsProps> = ({
  isRecording,
  barHeights,
  onRecordingStop,
  onRecordingStart,
  onTranscriptReceived,
}) => {
  const [backendStatus, setBackendStatus] = useState('Disconnected');
  const [isConnected, setIsConnected] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    connectToBackend();
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const connectToBackend = () => {
    try {
      const ws = new WebSocket('ws://localhost:9082');

      ws.onopen = () => {
        setIsConnected(true);
        setBackendStatus('Python backend active');
        onRecordingStart(); // Notify parent that backend is active
      };

      ws.onclose = () => {
        setIsConnected(false);
        setBackendStatus('Backend disconnected');
        onRecordingStop(); // Notify parent that backend is inactive
        // Auto-reconnect after 3 seconds
        setTimeout(connectToBackend, 3000);
      };

      ws.onerror = (error) => {
        console.error('RecordingControls WebSocket error:', error);
        setBackendStatus('Connection failed');
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          handleBackendMessage(data);
        } catch (error) {
          console.error('Failed to parse backend message:', error);
        }
      };

      wsRef.current = ws;
    } catch (error) {
      console.error('Failed to connect to backend:', error);
      setBackendStatus('Connection failed');
    }
  };

  const handleBackendMessage = (data: any) => {
    switch (data.type) {
      case 'status':
        setBackendStatus(data.message || 'Connected');
        setIsPaused(data.paused || false);
        break;
      case 'transcript':
        if (onTranscriptReceived && data.text) {
          onTranscriptReceived({ text: data.text, confidence: data.confidence || 0.8 });
        }
        break;
    }
  };

  const togglePause = () => {
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      const message = { type: isPaused ? 'resume' : 'pause' };
      wsRef.current.send(JSON.stringify(message));
    }
  };

  return (
    <div className="flex flex-col space-y-4">
      <div className="glass-card p-4">
        <div className="flex items-center justify-between">
          {/* Status Indicator */}
          <div className="flex items-center space-x-4">
            <div className={`status-dot ${
              isConnected ? (isPaused ? 'status-warning' : 'status-connected') : 'status-disconnected'
            } animate-glow`} />

            <div className="flex items-center space-x-3">
              {isConnected ? (
                isPaused ? <MicOff className="w-5 h-5 text-yellow-400" /> : <Mic className="w-5 h-5 text-green-400" />
              ) : (
                <WifiOff className="w-5 h-5 text-red-400" />
              )}

              <div className="flex flex-col">
                <span className="text-primary text-sm font-medium">
                  {backendStatus}
                </span>
                <span className="text-secondary text-xs">
                  {isPaused ? '⏸ Paused' : isConnected ? '🔴 Live' : '⚠️ Offline'}
                </span>
              </div>
            </div>
          </div>

          {/* Audio Visualization */}
          <div className="flex items-center space-x-1">
            {barHeights.map((height, index) => (
              <div
                key={index}
                className={`w-1 rounded-full transition-all duration-300 ${
                  isConnected && !isPaused
                    ? 'bg-gradient-to-t from-blue-500 to-green-400 shadow-lg shadow-blue-500/50'
                    : 'bg-white/20'
                }`}
                style={{
                  height: isConnected && !isPaused ? height : '6px',
                }}
              />
            ))}
          </div>

          {/* Control Button */}
          {isConnected && (
            <button
              onClick={togglePause}
              className={`btn ${
                isPaused
                  ? 'btn-success'
                  : 'btn-glass'
              }`}
            >
              <span className="flex items-center space-x-2">
                {isPaused ? (
                  <>
                    <span>▶️</span>
                    <span className="text-sm">Resume</span>
                  </>
                ) : (
                  <>
                    <span>⏸</span>
                    <span className="text-sm">Pause</span>
                  </>
                )}
              </span>
            </button>
          )}
        </div>
      </div>

      {/* Info Panel */}
      <div className="glass-card p-4">
        <div className="flex items-center space-x-3">
          <div className="text-blue-400 text-lg">
            {isConnected ? '🤖' : '⚠️'}
          </div>
          <div className="flex-1">
            <p className="text-primary text-sm font-medium mb-1">
              {isConnected ? 'Automated Processing' : 'Connection Required'}
            </p>
            <p className="text-secondary text-xs leading-relaxed">
              {isConnected
                ? 'Python backend is handling audio processing automatically. Real-time transcription and AI assistance are active.'
                : 'Waiting for Python backend connection. Check that brain_native.py is running.'
              }
            </p>
          </div>

          {/* Connection indicator */}
          <div className="flex flex-col items-center space-y-1">
            <div className={`w-8 h-8 rounded-full backdrop-blur-lg border transition-all duration-300 ${
              isConnected
                ? 'bg-green-500/20 border-green-400/50 shadow-lg shadow-green-400/30'
                : 'bg-red-500/20 border-red-400/50 shadow-lg shadow-red-400/30'
            }`}>
              {isConnected ? (
                <Wifi className="w-4 h-4 text-green-400 m-2" />
              ) : (
                <WifiOff className="w-4 h-4 text-red-400 m-2" />
              )}
            </div>
            <span className="text-xs text-tertiary font-mono">
              {isConnected ? 'WS' : 'OFF'}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};