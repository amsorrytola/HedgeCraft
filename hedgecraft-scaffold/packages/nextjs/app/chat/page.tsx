"use client";

import React, { useEffect, useRef, useState } from "react";
import {
  ArrowLeft,
  ExternalLink,
  Moon,
  Play,
  Send,
  Sparkles,
  Sun,
} from "lucide-react";
import { useAccount } from "wagmi";
import { Address } from "~~/components/scaffold-eth";

// small helper to generate unique ids
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 9);

interface Message {
  id: string;
  text: string;
  sender: "user" | "bot";
  timestamp: string; // ISO string so it's serializable
  txHash?: string;
  status?: "pending" | "success" | "error";
}

const ChatPage: React.FC = () => {
  const { address: connectedAddress } = useAccount();

  const [messages, setMessages] = useState<Message[]>(() => [
    {
      id: uid(),
      text:
        "Hey! 👋 I'm HedgeCraft Agent powered by LangGraph & Gemini 2.5 Flash. I can help you with:\n\n• Get the best hedging strategy\n• Open a hedged position\n• Check portfolio status\n• Collect earned fees\n• Close position",
      sender: "bot",
      timestamp: new Date().toISOString(),
    },
  ]);

  const [input, setInput] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [currentLoadingStep, setCurrentLoadingStep] = useState(0);
  const [loadingSteps, setLoadingSteps] = useState<string[]>([]);
  const [isDark, setIsDark] = useState(true);
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  const scrollToBottom = () => messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });

  useEffect(() => {
    scrollToBottom();
  }, [messages, currentLoadingStep]);

  const explorerBase = process.env.NEXT_PUBLIC_EXPLORER_BASE || "https://polygonscan.com/tx";

  const handleTxHashClick = (txHash: string) => {
    const url = `${explorerBase.replace(/\/$/, "")}/${txHash}`;
    window.open(url, "_blank", "noopener,noreferrer");
  };

  const handleNavigateToSimulation = () => {
    window.location.href = "/simulation";
  };

  const callLangGraphAgent = async (userMessage: string) => {
    const res = await fetch("/api/langgraph-agent", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: userMessage, from: connectedAddress }),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`API request failed: ${res.status} ${text}`);
    }

    const data = await res.json();
    return data as { response: string; txHash?: string; action?: string; loadingSteps?: string[] };
  };

  const pushMessage = (msg: Message) => setMessages((prev) => [...prev, msg]);

  const handleSendMessage = async () => {
    if (!input.trim()) return;

    const userMsg: Message = {
      id: uid(),
      text: input.trim(),
      sender: "user",
      timestamp: new Date().toISOString(),
    };

    pushMessage(userMsg);
    setInput("");
    setIsLoading(true);
    setCurrentLoadingStep(0);

    // optimistic bot placeholder
    const optimisticBotId = uid();
    const optimisticBotMsg: Message = {
      id: optimisticBotId,
      text: "Preparing your request...",
      sender: "bot",
      timestamp: new Date().toISOString(),
      status: "pending",
    };

    pushMessage(optimisticBotMsg);

    try {
      const result = await callLangGraphAgent(userMsg.text);

      const steps = Array.isArray(result.loadingSteps) ? result.loadingSteps : [];
      setLoadingSteps(steps);

      // animate steps but don't block UI for too long
      for (let i = 0; i < steps.length; i++) {
        if (!isLoading) break;
        // small readable delay
        // eslint-disable-next-line no-await-in-loop
        await new Promise((r) => setTimeout(r, 400));
        setCurrentLoadingStep(i + 1);
      }

      // Replace optimistic message with final bot message
      setMessages((prev) =>
        prev.map((m) =>
          m.id === optimisticBotId
            ? {
                ...m,
                text: result.response,
                txHash: result.txHash,
                status: result.txHash ? "success" : "success",
                timestamp: new Date().toISOString(),
              }
            : m,
        ),
      );
    } catch (err: any) {
      setMessages((prev) =>
        prev.map((m) =>
          m.id === optimisticBotId
            ? { ...m, text: `❌ Error: ${err.message || "Unknown"}`, status: "error", timestamp: new Date().toISOString() }
            : m,
        ),
      );
      console.error(err);
    } finally {
      setIsLoading(false);
      setCurrentLoadingStep(0);
      setLoadingSteps([]);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSendMessage();
    }
  };

  const quickActions = [
    { label: "🎯 Best Strategy", action: "What's the best hedging strategy?" },
    { label: "📊 Open Position", action: "Open a hedged position" },
    { label: "📈 Check Status", action: "Check my portfolio status" },
    { label: "💰 Collect Fees", action: "Collect my fees" },
    { label: "⚡ Execute", action: "Execute this strategy" },
    { label: "🔐 Close Position", action: "Close my position" },
  ];

  return (
    <div className={`min-h-screen flex flex-col ${isDark ? "bg-gray-900" : "bg-gradient-to-br from-purple-50 to-blue-50"}`}>
      {/* Header */}
      <header className={`${isDark ? "bg-gray-800/95" : "bg-white/95"} backdrop-blur-xl border-b ${isDark ? "border-purple-500/30" : "border-purple-200"} sticky top-0 z-50`}>
        <div className="max-w-7xl mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-4">
            <a href="/" className={`p-2 rounded-lg transition hover:${isDark ? "bg-gray-700" : "bg-gray-100"}`}>
              <ArrowLeft className="w-6 h-6" />
            </a>
            <div className="flex items-center gap-3">
              <div className={`w-11 h-11 rounded-xl flex items-center justify-center bg-gradient-to-br ${isDark ? "from-purple-500 to-pink-500" : "from-purple-400 to-pink-400"} shadow-lg`}>
                <Sparkles className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className={`text-xl font-bold ${isDark ? "text-white" : "text-gray-900"}`}>HedgeCraft Agent</h1>
                <p className={`text-xs ${isDark ? "text-gray-400" : "text-gray-600"}`}>LangGraph • Gemini 2.5 Flash</p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3">
            {connectedAddress && (
              <div className={`text-sm ${isDark ? "text-gray-300" : "text-gray-700"} px-4 py-2 rounded-lg ${isDark ? "bg-gray-700" : "bg-gray-100"}`}>
                <Address address={connectedAddress} />
              </div>
            )}
            <button onClick={handleNavigateToSimulation} className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gradient-to-r from-green-600 to-emerald-600 text-white hover:shadow-lg hover:shadow-green-500/50 transition font-medium">
              <Play className="w-4 h-4" />
              Simulation
            </button>
            <button onClick={() => setIsDark(!isDark)} className={`p-2 rounded-lg transition ${isDark ? "bg-gray-700 hover:bg-gray-600" : "bg-gray-200 hover:bg-gray-300"}`}>
              {isDark ? <Sun className="w-5 h-5 text-yellow-400" /> : <Moon className="w-5 h-5" />}
            </button>
          </div>
        </div>
      </header>

      {/* Main Chat */}
      <main className="flex-1 max-w-4xl mx-auto w-full px-6 py-8">
        <div className={`h-full rounded-2xl shadow-2xl overflow-hidden flex flex-col border ${isDark ? "bg-gray-800/60 border-purple-500/20" : "bg-white border-purple-200"}`}>
          {/* Messages */}
          <div className={`flex-1 overflow-y-auto p-8 space-y-6 ${isDark ? "bg-gray-900/40" : "bg-purple-50/50"}`}>
            {messages.map((msg) => (
              <div key={msg.id} className={`flex ${msg.sender === "user" ? "justify-end" : "justify-start"} animate-slideIn`}>
                <div className={`max-w-xl px-6 py-4 rounded-2xl ${msg.sender === "user" ? "bg-gradient-to-r from-purple-600 to-pink-600 text-white rounded-br-none shadow-lg" : `${isDark ? "bg-gray-800" : "bg-white"} text-gray-100 rounded-bl-none border ${isDark ? "border-purple-500/30" : "border-purple-200"}`}`}>
                  <p className="font-mono text-sm leading-relaxed whitespace-pre-wrap">{msg.text}</p>
                  {msg.txHash && (
                    <button onClick={() => handleTxHashClick(msg.txHash!)} className="mt-4 pt-4 border-t border-gray-500/30 flex items-center gap-2 text-xs hover:opacity-100 opacity-75 transition group">
                      <code className="break-all">{msg.txHash}</code>
                      <ExternalLink className="w-4 h-4 group-hover:scale-110 transition" />
                    </button>
                  )}
                  <p className={`text-xs mt-2 opacity-60`}>{new Date(msg.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</p>
                </div>
              </div>
            ))}

            {isLoading && loadingSteps.length > 0 && (
              <div className="flex justify-start animate-slideIn">
                <div className={`px-6 py-4 rounded-2xl rounded-bl-none border ${isDark ? "bg-gray-800 border-purple-500/30" : "bg-white border-purple-200"}`}>
                  {currentLoadingStep === 0 ? (
                    <div className="flex gap-2">
                      <div className={`w-2 h-2 rounded-full animate-bounce ${isDark ? "bg-purple-400" : "bg-purple-500"}`}></div>
                      <div className={`w-2 h-2 rounded-full animate-bounce ${isDark ? "bg-purple-400" : "bg-purple-500"}`} style={{ animationDelay: "0.15s" }}></div>
                      <div className={`w-2 h-2 rounded-full animate-bounce ${isDark ? "bg-purple-400" : "bg-purple-500"}`} style={{ animationDelay: "0.3s" }}></div>
                    </div>
                  ) : (
                    <div className="space-y-2 max-w-sm">
                      {loadingSteps.map((step, idx) => (
                        <div key={idx} className={`flex items-center gap-2 text-sm transition ${idx < currentLoadingStep ? "opacity-60" : "opacity-100 font-semibold"}`}>
                          {idx < currentLoadingStep ? <span className="text-green-500">✓</span> : <span className="animate-spin">⚙️</span>}
                          {step}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          {/* Input */}
          <div className={`${isDark ? "bg-gray-800 border-t border-gray-700" : "bg-white border-t border-purple-200"} p-6`}>
            <div className="flex gap-3">
              <textarea value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={handleKeyPress} placeholder="Ask me anything about hedging strategies..." disabled={isLoading} className={`flex-1 px-6 py-4 rounded-xl resize-none focus:outline-none focus:ring-2 focus:ring-purple-500 transition ${isDark ? "bg-gray-700 text-white placeholder-gray-400 border border-gray-600" : "bg-gray-50 text-gray-900 placeholder-gray-500 border border-purple-200"}`} rows={2} />
              <button onClick={handleSendMessage} disabled={!input.trim() || isLoading} className="bg-gradient-to-r from-purple-600 to-pink-600 text-white px-6 py-4 rounded-xl hover:shadow-lg hover:shadow-purple-500/50 transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center">
                <Send className="w-5 h-5" />
              </button>
            </div>
          </div>
        </div>

        {/* Quick Actions */}
        <div className="mt-8 grid grid-cols-2 md:grid-cols-3 gap-3">
          {quickActions.map((btn) => (
            <button key={btn.action} onClick={() => setInput(btn.action)} disabled={isLoading} className={`p-3 rounded-lg text-sm font-medium transition disabled:opacity-50 ${isDark ? "bg-gray-800 hover:bg-gray-700 text-purple-400" : "bg-white hover:bg-gray-50 text-purple-600 border border-purple-200"}`}>
              {btn.label}
            </button>
          ))}
        </div>
      </main>

      <style jsx>{`
        @keyframes slideIn {
          from {
            opacity: 0;
            transform: translateY(10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
        .animate-slideIn {
          animation: slideIn 0.3s ease-out forwards;
        }
      `}</style>
    </div>
  );
};

export default ChatPage;
