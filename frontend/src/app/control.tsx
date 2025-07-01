'use client';

import { useState, useEffect } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';

interface TranscriptionStats {
  isConnected: boolean;
  latency: number;
  wordsPerMinute: number;
  accuracy: number;
  backendStatus?: string;
}

export default function ControlPanel() {
  const [isHudVisible, setIsHudVisible] = useState(false);
  const [stats, setStats] = useState<TranscriptionStats>({
    isConnected: false,
    latency: 0,
    wordsPerMinute: 0,
    accuracy: 0,
    backendStatus: 'Disconnected'
  });
  const [hudWindow, setHudWindow] = useState<WebviewWindow | null>(null);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [wsConnection, setWsConnection] = useState<WebSocket | null>(null);

  // Connect to Python backend WebSocket
  useEffect(() => {
    connectToBackend();
    return () => {
      if (wsConnection) {
        wsConnection.close();
      }
    };
  }, []);

  const connectToBackend = () => {
    try {
      const ws = new WebSocket('ws://localhost:9082');

      ws.onopen = () => {
        console.log('Connected to Python backend');
        setStats(prev => ({ ...prev, isConnected: true, backendStatus: 'Connected to Python Backend' }));
        setConnectionError(null);
      };

      ws.onclose = () => {
        console.log('Disconnected from Python backend');
        setStats(prev => ({ ...prev, isConnected: false, backendStatus: 'Disconnected - Check backend' }));
        setConnectionError('Backend disconnected');
        // Attempt to reconnect after 3 seconds
        setTimeout(connectToBackend, 3000);
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setConnectionError('Backend connection failed');
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          handleBackendMessage(data);
        } catch (error) {
          console.error('Failed to parse backend message:', error);
        }
      };

      setWsConnection(ws);
    } catch (error) {
      console.error('Failed to connect to backend:', error);
      setConnectionError('Failed to connect to backend');
      // Retry connection after 3 seconds
      setTimeout(connectToBackend, 3000);
    }
  };

  const handleBackendMessage = (data: any) => {
    switch (data.type) {
      case 'status':
        setStats(prev => ({
          ...prev,
          backendStatus: data.message || data.status || 'Connected'
        }));
        break;
      case 'advisor_keywords':
        // Forward to HUD if visible
        if (hudWindow && data.text) {
          hudWindow.emit('advisor-response', { text: data.text });
        }
        console.log('Advisor response:', data.text);
        break;
      default:
        console.log('Unknown message type:', data);
    }
  };

  const sendToBackend = (data: any) => {
    if (wsConnection && wsConnection.readyState === WebSocket.OPEN) {
      wsConnection.send(JSON.stringify(data));
    }
  };

  const toggleHud = async () => {
    try {
      if (!isHudVisible) {
        // Create and show HUD window
        const hud = new WebviewWindow('hud', {
          url: '/hud',
          width: 800,
          height: 120,
          resizable: false,
          decorations: false,
          transparent: true,
          alwaysOnTop: true,
          skipTaskbar: true,
          center: true
        });

        await hud.once('tauri://created', () => {
          console.log('HUD window created');
        });

        setHudWindow(hud);
        setIsHudVisible(true);
      } else {
        // Hide HUD window
        if (hudWindow) {
          await hudWindow.hide();
          setIsHudVisible(false);
        }
      }
    } catch (error) {
      console.error('Failed to toggle HUD:', error);
    }
  };

  return (
    <div className="min-h-screen p-6 flex items-center justify-center">
      <div className="max-w-md w-full space-y-6 animate-float">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-2xl font-bold text-primary mb-2">Earshot Copilot</h1>
          <p className="text-secondary">AI-Powered Real-time Assistant</p>
        </div>

        {/* Connection Status */}
        <div className="glass-card p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium text-primary">Python Backend</span>
            <div className={`status-dot ${stats.isConnected ? 'status-connected' : 'status-disconnected'} animate-glow`} />
          </div>
          <div className="text-xs text-secondary">
            {stats.backendStatus}
          </div>
          {connectionError && (
            <div className="text-xs text-red-300 mt-2 glass-card p-2 bg-red-500/10 border border-red-500/20">
              {connectionError}
            </div>
          )}
        </div>

        {/* HUD Controls */}
        <div className="glass-card p-4">
          <h3 className="text-sm font-medium text-primary mb-3">HUD Display</h3>
          <button
            onClick={toggleHud}
            className={`w-full py-2 btn ${
              isHudVisible
                ? 'btn-primary'
                : 'btn-glass'
            }`}
          >
            {isHudVisible ? 'Hide HUD' : 'Show HUD'}
          </button>
        </div>

        {/* Performance Stats */}
        {stats.isConnected && (
          <div className="glass-card p-4">
            <h3 className="text-sm font-medium text-primary mb-3">Live Stats</h3>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div className="glass-card p-3">
                <div className="text-tertiary text-xs uppercase tracking-wide">Status</div>
                <div className="font-mono text-green-400 font-medium">Active</div>
              </div>
              <div className="glass-card p-3">
                <div className="text-tertiary text-xs uppercase tracking-wide">Backend</div>
                <div className="font-mono text-blue-400 text-xs">Python-Native</div>
              </div>
            </div>
          </div>
        )}

        {/* Quick Settings */}
        <div className="glass-card p-4">
          <h3 className="text-sm font-medium text-primary mb-3">Quick Settings</h3>
          <div className="space-y-3 text-sm">
            <label className="flex items-center cursor-pointer group">
              <input type="checkbox" className="mr-3" defaultChecked />
              <span className="text-secondary group-hover:text-primary transition-colors">Show AI responses</span>
            </label>
            <label className="flex items-center cursor-pointer group">
              <input type="checkbox" className="mr-3" defaultChecked />
              <span className="text-secondary group-hover:text-primary transition-colors">Auto-fade old text</span>
            </label>
            <label className="flex items-center cursor-pointer group">
              <input type="checkbox" className="mr-3" />
              <span className="text-secondary group-hover:text-primary transition-colors">Debug mode</span>
            </label>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center text-xs text-tertiary space-y-1">
          <p className="font-light">Earshot Copilot - Python-Native Architecture</p>
          <p>Backend: {stats.isConnected ? '🟢 Ready' : '🔴 Connecting...'}</p>
          <p className="font-mono">WebSocket: {stats.isConnected ? 'ws://localhost:9082 ✓' : 'Disconnected'}</p>
        </div>
      </div>
    </div>
  );
}