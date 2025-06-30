'use client';

import { useState, useEffect } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { WebviewWindow } from '@tauri-apps/api/webviewWindow';
import { invoke } from '@tauri-apps/api/core';

interface TranscriptionStats {
  isConnected: boolean;
  latency: number;
  wordsPerMinute: number;
  accuracy: number;
}

export default function ControlPanel() {
  const [isHudVisible, setIsHudVisible] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [stats, setStats] = useState<TranscriptionStats>({
    isConnected: false,
    latency: 0,
    wordsPerMinute: 0,
    accuracy: 0
  });
  const [hudWindow, setHudWindow] = useState<WebviewWindow | null>(null);

  useEffect(() => {
    checkWhisperConnection();
    const interval = setInterval(checkWhisperConnection, 5000);
    return () => clearInterval(interval);
  }, []);

  const checkWhisperConnection = async () => {
    try {
      const response = await fetch('http://localhost:8080/');
      setStats(prev => ({ ...prev, isConnected: response.ok }));
    } catch (error) {
      setStats(prev => ({ ...prev, isConnected: false }));
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

  const startRecording = async () => {
    try {
      // Start audio capture and transcription
      setIsRecording(true);

      // If HUD is visible, notify it to start displaying transcriptions
      if (hudWindow) {
        await hudWindow.emit('start-transcription', {});
      }
    } catch (error) {
      console.error('Failed to start recording:', error);
      setIsRecording(false);
    }
  };

  const stopRecording = async () => {
    try {
      setIsRecording(false);

      // Notify HUD to stop
      if (hudWindow) {
        await hudWindow.emit('stop-transcription', {});
      }
    } catch (error) {
      console.error('Failed to stop recording:', error);
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white p-6">
      <div className="max-w-md mx-auto space-y-6">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-2xl font-bold mb-2">Earshot</h1>
          <p className="text-gray-400">Real-time Transcription HUD</p>
        </div>

        {/* Connection Status */}
        <div className="bg-gray-800 rounded-lg p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium">Whisper Backend</span>
            <div className={`w-3 h-3 rounded-full ${stats.isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
          </div>
          <div className="text-xs text-gray-400">
            {stats.isConnected ? 'Connected to localhost:8080' : 'Disconnected - Check backend'}
          </div>
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

        {/* Recording Controls */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="text-sm font-medium mb-3">Transcription</h3>
          <button
            onClick={isRecording ? stopRecording : startRecording}
            disabled={!stats.isConnected}
            className={`w-full py-3 px-4 rounded-md font-medium transition-colors ${
              isRecording
                ? 'bg-red-600 hover:bg-red-700'
                : 'bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed'
            }`}
          >
            {isRecording ? '⏹ Stop Recording' : '🎤 Start Recording'}
          </button>

          {!stats.isConnected && (
            <p className="text-xs text-red-400 mt-2">
              Whisper backend required for recording
            </p>
          )}
        </div>

        {/* Performance Stats */}
        {isRecording && (
          <div className="bg-gray-800 rounded-lg p-4">
            <h3 className="text-sm font-medium mb-3">Live Stats</h3>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <div className="text-gray-400">Latency</div>
                <div className="font-mono">{stats.latency}ms</div>
              </div>
              <div>
                <div className="text-gray-400">WPM</div>
                <div className="font-mono">{stats.wordsPerMinute}</div>
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
              Show confidence scores
            </label>
            <label className="flex items-center">
              <input type="checkbox" className="mr-2" defaultChecked />
              Auto-fade old words
            </label>
            <label className="flex items-center">
              <input type="checkbox" className="mr-2" />
              Filter low confidence
            </label>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center text-xs text-gray-500">
          <p>Sprint 2: Real-time HUD Implementation</p>
          <p>Backend: {stats.isConnected ? 'Ready' : 'Waiting...'}</p>
        </div>
      </div>
    </div>
  );
}