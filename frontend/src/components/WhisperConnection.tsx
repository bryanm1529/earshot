'use client';

import { useEffect, useRef, useState } from 'react';

interface WhisperConnectionProps {
  isActive: boolean;
  onTranscription: (words: string[], confidence: number) => void;
  onLatencyUpdate: (latency: number) => void;
  onError: (error: string) => void;
}

export function WhisperConnection({
  isActive,
  onTranscription,
  onLatencyUpdate,
  onError
}: WhisperConnectionProps) {
  const [isConnected, setIsConnected] = useState(false);
  const [backendStatus, setBackendStatus] = useState('Disconnected');
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    if (isActive) {
      connectToBackend();
    } else {
      disconnectFromBackend();
    }

    return () => {
      disconnectFromBackend();
    };
  }, [isActive]);

  const connectToBackend = () => {
    try {
      const ws = new WebSocket('ws://localhost:9082');

      ws.onopen = () => {
        console.log('WhisperConnection: Connected to Python backend');
        setIsConnected(true);
        setBackendStatus('Connected to Cognitive Engine');
        onLatencyUpdate(50); // Placeholder latency for Python backend
      };

      ws.onclose = () => {
        console.log('WhisperConnection: Disconnected from Python backend');
        setIsConnected(false);
        setBackendStatus('Disconnected');
        onError('Backend connection lost');
      };

      ws.onerror = (error) => {
        console.error('WhisperConnection WebSocket error:', error);
        onError('Backend connection failed');
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
      onError('Failed to connect to Python backend');
    }
  };

  const disconnectFromBackend = () => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
      setIsConnected(false);
      setBackendStatus('Disconnected');
    }
  };

  const handleBackendMessage = (data: any) => {
    switch (data.type) {
      case 'status':
        setBackendStatus(data.message || data.status || 'Connected');
        break;
      case 'transcript':
        // Convert transcript text to words array and call onTranscription
        if (data.text && data.text.trim()) {
          const words = data.text.trim().split(' ');
          const confidence = data.confidence || 0.8;
          onTranscription(words, confidence);
        }
        break;
      case 'advisor_keywords':
        // This could be handled here or passed up to parent
        console.log('Advisor response received:', data.text);
        break;
      default:
        console.log('Unknown message type from backend:', data.type);
    }
  };

  // This component doesn't render anything visible - it's just for backend communication
  return (
    <div className="hidden">
      {/* Hidden status indicator for debugging */}
      <div className="text-xs text-gray-500">
        Python Backend: {backendStatus}
        {isConnected && ' (Active)'}
      </div>
    </div>
  );
}