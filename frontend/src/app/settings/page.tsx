'use client';

import React from 'react';
import { Bell, User, Lock, Database, Palette, ArrowLeft, Mic, Bot } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function SettingsPage() {
  const router = useRouter();

  const settingsSections = [
    {
      title: 'Account',
      icon: <User className="w-5 h-5" />,
      items: ['Profile', 'Email', 'Password']
    },
    {
      title: 'AI Assistant',
      icon: <Bot className="w-5 h-5" />,
      items: ['Model Selection', 'Response Style', 'API Keys', 'Processing Speed']
    },
    {
      title: 'Audio & Recording',
      icon: <Mic className="w-5 h-5" />,
      items: ['Microphone Settings', 'Audio Quality', 'Noise Reduction', 'Hotkeys']
    },
    {
      title: 'Notifications',
      icon: <Bell className="w-5 h-5" />,
      items: ['System Alerts', 'Connection Status', 'Error Notifications']
    },
    {
      title: 'Privacy',
      icon: <Lock className="w-5 h-5" />,
      items: ['Data Processing', 'Local Storage', 'Audio Privacy']
    },
    {
      title: 'Storage',
      icon: <Database className="w-5 h-5" />,
      items: ['Cache Management', 'Audio Logs', 'Auto-cleanup']
    },
    {
      title: 'Appearance',
      icon: <Palette className="w-5 h-5" />,
      items: ['Theme', 'HUD Settings', 'Font Size', 'Transparency']
    }
  ];

  return (
    <div className="min-h-screen p-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex items-center gap-4 mb-8">
          <button
            onClick={() => router.back()}
            className="btn-glass p-2 hover-lift"
          >
            <ArrowLeft className="w-5 h-5 text-secondary" />
          </button>
          <h1 className="text-3xl font-bold text-primary">Settings</h1>
        </div>

        <div className="space-y-6">
          {settingsSections.map((section) => (
            <div key={section.title} className="glass-card p-6">
              <div className="flex items-center gap-3 mb-4">
                <div className="text-blue-400">
                  {section.icon}
                </div>
                <h2 className="text-xl font-semibold text-primary">{section.title}</h2>
              </div>
              <div className="space-y-3">
                {section.items.map((item) => (
                  <div key={item} className="flex items-center justify-between p-3 glass-card hover-lift cursor-pointer">
                    <span className="text-secondary">{item}</span>
                    <button className="btn-glass px-3 py-1 text-sm">Configure</button>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
