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
  // Keep a ref to access current state without triggering re-renders
  const stateRef = useRef(state);
  stateRef.current = state;

  // Simplified functions for external control

  const connect = useCallback(() => {
    // Force reconnection by closing current connection and clearing manual close flag
    isManualClose.current = false;

    if (wsRef.current) {
      wsRef.current.close();
    }

    // The useEffect will handle the reconnection automatically
  }, []);

  const disconnect = useCallback(() => {
    isManualClose.current = true;

    // Clear timeouts
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }

    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    setState(prev => ({
      ...prev,
      isConnected: false
    }));
  }, []);

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

  // Initialize connection only once on mount
  useEffect(() => {
    isManualClose.current = false;

    // Initialize WebSocket connection
    const initConnection = () => {
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        return; // Already connected
      }

      console.log('Connecting to advisor stream:', wsUrl);

      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('✅ Connected to advisor stream');
        setState(prev => ({
          ...prev,
          isConnected: true,
          connectionAttempts: 0
        }));

        // Start ping interval
        pingIntervalRef.current = setInterval(() => {
          if (wsRef.current?.readyState === WebSocket.OPEN) {
            wsRef.current.send(JSON.stringify({ type: 'ping', timestamp: Date.now() }));
          }
        }, 30000);
      };

      ws.onmessage = (event: MessageEvent) => {
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
      };

      ws.onclose = (event) => {
        console.log('🔌 Advisor stream disconnected:', event.code, event.reason);
        if (stateRef.current.isConnected) {
          setState(prev => ({
            ...prev,
            isConnected: false
          }));
        }

        // Clear intervals
        if (pingIntervalRef.current) {
          clearInterval(pingIntervalRef.current);
          pingIntervalRef.current = null;
        }

        // Auto-reconnect unless manually closed
        if (!isManualClose.current) {
          const delay = Math.min(1000 * Math.pow(2, stateRef.current.connectionAttempts), 10000);
          console.log(`🔄 Reconnecting to advisor stream in ${delay}ms...`);

          setState(prev => ({
            ...prev,
            connectionAttempts: prev.connectionAttempts + 1
          }));

          reconnectTimeoutRef.current = setTimeout(() => {
            initConnection();
          }, delay);
        }
      };

      ws.onerror = (error) => {
        console.error('❌ Advisor stream error:', error);
        if (stateRef.current.isConnected) {
          setState(prev => ({
            ...prev,
            isConnected: false
          }));
        }
      };
    };

    // Start initial connection
    initConnection();

    // Cleanup on unmount
    return () => {
      isManualClose.current = true;

      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
        reconnectTimeoutRef.current = null;
      }
      if (pingIntervalRef.current) {
        clearInterval(pingIntervalRef.current);
        pingIntervalRef.current = null;
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [wsUrl]); // Only depend on wsUrl, run once when URL changes

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