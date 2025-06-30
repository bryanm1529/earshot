import { useEffect, useRef, useState, useCallback } from 'react';

interface AdvisorMessage {
  type: 'advisor_keywords' | 'status' | 'pong';
  text?: string;
  status?: string;
  paused?: boolean;
  timestamp: number;
}

interface AdvisorStreamState {
  isConnected: boolean;
  isPaused: boolean;
  lastMessage: string | null;
  lastTimestamp: number | null;
  connectionAttempts: number;
}

export const useAdvisorStream = (wsUrl: string = 'ws://localhost:9082') => {
  const [state, setState] = useState<AdvisorStreamState>({
    isConnected: false,
    isPaused: false,
    lastMessage: null,
    lastTimestamp: null,
    connectionAttempts: 0
  });

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const pingIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const isManualClose = useRef(false);

  const clearTimeouts = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }
  }, []);

  const startPingInterval = useCallback(() => {
    clearTimeouts();
    // Send ping every 30 seconds to keep connection alive
    pingIntervalRef.current = setInterval(() => {
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({ type: 'ping', timestamp: Date.now() }));
      }
    }, 30000);
  }, [clearTimeouts]);

  const handleMessage = useCallback((event: MessageEvent) => {
    try {
      const message: AdvisorMessage = JSON.parse(event.data);

      // Check for stale messages (older than 5 seconds)
      const now = Date.now();
      const messageAge = now - message.timestamp;
      if (messageAge > 5000) {
        console.debug('Discarding stale message:', messageAge + 'ms old');
        return;
      }

      switch (message.type) {
        case 'advisor_keywords':
          if (message.text) {
            setState(prev => ({
              ...prev,
              lastMessage: message.text!,
              lastTimestamp: message.timestamp
            }));
          }
          break;
        case 'status':
          setState(prev => ({
            ...prev,
            isPaused: message.paused || false
          }));
          break;
        case 'pong':
          // Pong received, connection is healthy
          break;
        default:
          console.debug('Unknown message type:', message.type);
      }
    } catch (error) {
      console.error('Error parsing advisor message:', error);
    }
  }, []);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return; // Already connected
    }

    console.log('Connecting to advisor stream:', wsUrl);

    setState(prev => ({
      ...prev,
      connectionAttempts: prev.connectionAttempts + 1
    }));

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      console.log('✅ Connected to advisor stream');
      setState(prev => ({
        ...prev,
        isConnected: true,
        connectionAttempts: 0
      }));
      startPingInterval();
    };

    ws.onmessage = handleMessage;

    ws.onclose = (event) => {
      console.log('🔌 Advisor stream disconnected:', event.code, event.reason);
      setState(prev => ({
        ...prev,
        isConnected: false
      }));
      clearTimeouts();

      // Auto-reconnect unless manually closed
      if (!isManualClose.current) {
        const delay = Math.min(1000 * Math.pow(2, state.connectionAttempts), 10000); // Exponential backoff, max 10s
        console.log(`🔄 Reconnecting to advisor stream in ${delay}ms...`);

        reconnectTimeoutRef.current = setTimeout(() => {
          connect();
        }, delay);
      }
    };

    ws.onerror = (error) => {
      console.error('❌ Advisor stream error:', error);
      setState(prev => ({
        ...prev,
        isConnected: false
      }));
    };
  }, [wsUrl, handleMessage, startPingInterval, clearTimeouts, state.connectionAttempts]);

  const disconnect = useCallback(() => {
    isManualClose.current = true;
    clearTimeouts();

    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    setState(prev => ({
      ...prev,
      isConnected: false
    }));
  }, [clearTimeouts]);

  const sendPause = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'pause', timestamp: Date.now() }));
    }
  }, []);

  const sendResume = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'resume', timestamp: Date.now() }));
    }
  }, []);

  // Initialize connection on mount
  useEffect(() => {
    isManualClose.current = false;
    connect();

    // Cleanup on unmount
    return () => {
      isManualClose.current = true;
      clearTimeouts();
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [connect, clearTimeouts]);

  return {
    isConnected: state.isConnected,
    isPaused: state.isPaused,
    lastMessage: state.lastMessage,
    lastTimestamp: state.lastTimestamp,
    connectionAttempts: state.connectionAttempts,
    sendPause,
    sendResume,
    disconnect,
    reconnect: connect
  };
};