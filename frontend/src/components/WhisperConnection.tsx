'use client';

import { useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface WhisperSegment {
  text: string;
  start: number;
  end: number;
  confidence?: number;
}

interface WhisperResponse {
  segments: WhisperSegment[];
  buffer_size_ms: number;
}

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
  const [systemAudioDevice, setSystemAudioDevice] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);

  // Check for system audio device on component mount
  useEffect(() => {
    checkSystemAudioDevice();
  }, []);

  // Handle start/stop based on isActive prop
  useEffect(() => {
    if (isActive && !isCapturing) {
      startNativeAudioCapture();
    } else if (!isActive && isCapturing) {
      stopNativeAudioCapture();
    }
  }, [isActive, isCapturing]);

  const checkSystemAudioDevice = async () => {
    try {
      console.log('Checking for system audio device...');
      const device = await invoke<string>('check_system_audio_device');
      console.log('System audio device found:', device);
      setSystemAudioDevice(device);
    } catch (error) {
      console.error('System audio device not available:', error);
      const errorMessage = typeof error === 'string' ? error : 'Unknown system audio error';
      onError(`System audio not available: ${errorMessage}`);
      setSystemAudioDevice(null);
    }
  };

  const startNativeAudioCapture = async () => {
    if (isCapturing) {
      console.log('Audio capture already active');
      return;
    }

    try {
      console.log('Starting native system audio capture...');
      setIsCapturing(true);

      await invoke('start_native_audio_capture');
      console.log('Native audio capture started successfully');

      // Update latency - native capture should be much faster
      onLatencyUpdate(50); // Placeholder latency for native capture

    } catch (error) {
      console.error('Failed to start native audio capture:', error);
      const errorMessage = typeof error === 'string' ? error : 'Failed to start system audio capture';
      onError(errorMessage);
      setIsCapturing(false);
    }
  };

  const stopNativeAudioCapture = async () => {
    if (!isCapturing) {
      console.log('Audio capture already stopped');
      return;
    }

    try {
      console.log('Stopping native audio capture...');
      await invoke('stop_native_audio_capture');
      console.log('Native audio capture stopped successfully');
      setIsCapturing(false);
    } catch (error) {
      console.error('Failed to stop native audio capture:', error);
      const errorMessage = typeof error === 'string' ? error : 'Failed to stop system audio capture';
      onError(errorMessage);
      // Still set to false since we attempted to stop
      setIsCapturing(false);
    }
  };

  // This component doesn't render anything - it's just for audio processing coordination
  return (
    <div className="hidden">
      {/* Hidden status indicator for debugging */}
      <div className="text-xs text-gray-500">
        System Audio: {systemAudioDevice || 'Not Available'}
        {isCapturing && ' (Capturing)'}
      </div>
    </div>
  );
}