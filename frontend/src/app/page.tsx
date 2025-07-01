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
        setStats(prev => ({ ...prev, isConnected: true, backendStatus: 'Connected to Cognitive Engine' }));
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
      case 'transcript':
        // Forward transcription to HUD window
        if (hudWindow) {
          hudWindow.emit('transcription-data', {
            words: data.text?.split(' ') || [],
            confidence: data.confidence || 0.8
          });
        }
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

  const pauseSystem = () => {
    sendToBackend({ type: 'pause' });
  };

  const resumeSystem = () => {
    sendToBackend({ type: 'resume' });
  };

  return (
    <div className="min-h-screen p-8 flex items-center justify-center">
      <div className="w-full max-w-md space-y-6 animate-float">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="relative">
            <h1 className="text-4xl font-light text-primary mb-2 tracking-tight">
              Earshot
            </h1>
            <div className="text-lg font-medium bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
              Copilot
            </div>
            <p className="text-secondary text-sm mt-3 font-light">
              AI-Powered Real-time Assistant
            </p>
          </div>
        </div>

        {/* Python Backend Status */}
        <div className="glass-card p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-3">
              <div className={`status-dot ${stats.isConnected ? 'status-connected' : 'status-disconnected'} animate-glow`} />
              <span className="text-primary font-medium">Python Backend</span>
            </div>
            <div className="text-xs text-tertiary font-mono">
              {stats.isConnected ? 'ONLINE' : 'OFFLINE'}
            </div>
          </div>
          <div className="text-sm text-secondary mb-2">
            {stats.backendStatus}
          </div>
          {connectionError && (
            <div className="text-xs text-red-300 bg-red-500/10 border border-red-500/20 rounded-lg p-2 mt-2">
              {connectionError}
            </div>
          )}
        </div>

        {/* System Status */}
        <div className="glass-card p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center space-x-3">
              <div className={`status-dot ${stats.isConnected ? 'status-connected' : 'status-warning'}`} />
              <span className="text-primary font-medium">Audio Processing</span>
            </div>
            <div className="text-xs px-2 py-1 rounded-full bg-white/10 text-secondary font-mono">
              {stats.isConnected ? 'ACTIVE' : 'STANDBY'}
            </div>
          </div>
          <div className="text-sm text-secondary">
            {stats.isConnected ?
              '✨ Audio pipeline active (Python-native)' :
              '⏳ Waiting for backend connection'
            }
          </div>
        </div>

        {/* HUD Controls */}
        <div className="glass-card p-6">
          <h3 className="text-primary font-medium mb-4">HUD Display</h3>
          <button
            onClick={toggleHud}
            className={`w-full py-3 btn ${
              isHudVisible
                ? 'btn-primary transform scale-105'
                : 'btn-glass'
            }`}
          >
            <span className="flex items-center justify-center space-x-2">
              <span>{isHudVisible ? '👁️ Hide HUD' : '👁️ Show HUD'}</span>
            </span>
          </button>
        </div>

        {/* System Controls */}
        <div className="glass-card p-6">
          <h3 className="text-primary font-medium mb-4">System Control</h3>
          <div className="grid grid-cols-2 gap-3">
            <button
              onClick={pauseSystem}
              disabled={!stats.isConnected}
              className="btn btn-glass py-3 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <span className="flex items-center justify-center space-x-2">
                <span>⏸</span>
                <span>Pause</span>
              </span>
            </button>
            <button
              onClick={resumeSystem}
              disabled={!stats.isConnected}
              className="btn btn-success py-3 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <span className="flex items-center justify-center space-x-2">
                <span>▶️</span>
                <span>Resume</span>
              </span>
            </button>
          </div>

          <div className="mt-4 p-4 glass-card">
            <div className="flex items-start space-x-3">
              <div className="text-blue-400 text-lg">ℹ️</div>
              <div>
                <p className="text-primary text-sm font-medium mb-1">Auto Processing</p>
                <p className="text-secondary text-xs leading-relaxed">
                  The Python backend handles all audio processing automatically. Use pause/resume to control the system.
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Performance Stats */}
        {stats.isConnected && (
          <div className="glass-card p-6">
            <h3 className="text-primary font-medium mb-4">System Stats</h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="glass-card p-4 text-center">
                <div className="text-tertiary text-xs uppercase tracking-wide mb-1">Status</div>
                <div className="text-green-400 font-mono font-medium">Active</div>
              </div>
              <div className="glass-card p-4 text-center">
                <div className="text-tertiary text-xs uppercase tracking-wide mb-1">Pipeline</div>
                <div className="text-blue-400 font-mono text-sm">Python-Native</div>
              </div>
            </div>
          </div>
        )}

        {/* Quick Settings */}
        <div className="glass-card p-6">
          <h3 className="text-primary font-medium mb-4">Display Settings</h3>
          <div className="space-y-3">
            <label className="flex items-center space-x-3 cursor-pointer group">
              <input type="checkbox" defaultChecked />
              <span className="text-secondary text-sm group-hover:text-primary transition-colors">Show AI responses</span>
            </label>
            <label className="flex items-center space-x-3 cursor-pointer group">
              <input type="checkbox" defaultChecked />
              <span className="text-secondary text-sm group-hover:text-primary transition-colors">Auto-fade old text</span>
            </label>
            <label className="flex items-center space-x-3 cursor-pointer group">
              <input type="checkbox" />
              <span className="text-secondary text-sm group-hover:text-primary transition-colors">Debug mode</span>
            </label>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center text-tertiary text-xs space-y-1 pt-4">
          <p className="font-light">Earshot Copilot - Python-Native Architecture</p>
          <p>Backend: {stats.isConnected ? '🟢 Ready' : '🔴 Connecting...'}</p>
          <p className="font-mono text-xs">
            {stats.isConnected ? 'ws://localhost:9082 ✓' : 'Connection pending...'}
          </p>
        </div>
      </div>
    </div>
  );
}
