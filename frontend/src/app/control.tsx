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
    <div className="min-h-screen bg-gray-900 text-white p-6">
      <div className="max-w-md mx-auto space-y-6">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-2xl font-bold mb-2">Earshot Copilot</h1>
          <p className="text-gray-400">AI-Powered Real-time Assistant</p>
        </div>

        {/* Connection Status */}
        <div className="bg-gray-800 rounded-lg p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium">Python Backend</span>
            <div className={`w-3 h-3 rounded-full ${stats.isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
          </div>
          <div className="text-xs text-gray-400">
            {stats.backendStatus}
          </div>
          {connectionError && (
            <div className="text-xs text-red-400 mt-2">
              {connectionError}
            </div>
          )}
        </div>

        {/* HUD Controls */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="text-sm font-medium mb-3">HUD Display</h3>
          <button
            onClick={toggleHud}
            className={`w-full py-2 px-4 rounded-md font-medium transition-colors ${
              isHudVisible
                ? 'bg-blue-600 hover:bg-blue-700'
                : 'bg-gray-700 hover:bg-gray-600'
            }`}
          >
            {isHudVisible ? 'Hide HUD' : 'Show HUD'}
          </button>
        </div>

        {/* Performance Stats */}
        {stats.isConnected && (
          <div className="bg-gray-800 rounded-lg p-4">
            <h3 className="text-sm font-medium mb-3">Live Stats</h3>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <div className="text-gray-400">Status</div>
                <div className="font-mono text-green-400">Active</div>
              </div>
              <div>
                <div className="text-gray-400">Backend</div>
                <div className="font-mono text-xs">Python-Native</div>
              </div>
            </div>
          </div>
        )}

        {/* Quick Settings */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="text-sm font-medium mb-3">Quick Settings</h3>
          <div className="space-y-2 text-sm">
            <label className="flex items-center">
              <input type="checkbox" className="mr-2" defaultChecked />
              Show AI responses
            </label>
            <label className="flex items-center">
              <input type="checkbox" className="mr-2" defaultChecked />
              Auto-fade old text
            </label>
            <label className="flex items-center">
              <input type="checkbox" className="mr-2" />
              Debug mode
            </label>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center text-xs text-gray-500">
          <p>Earshot Copilot - Python-Native Architecture</p>
          <p>Backend: {stats.isConnected ? 'Ready' : 'Connecting...'}</p>
          <p>WebSocket: {stats.isConnected ? 'ws://localhost:9082' : 'Disconnected'}</p>
        </div>
      </div>
    </div>
  );
}