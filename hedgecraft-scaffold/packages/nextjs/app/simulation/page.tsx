"use client";

import React, { useEffect, useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ArrowLeft, Play, Pause, RotateCcw } from "lucide-react";
import Link from "next/link";

interface DataPoint {
  x: number;
  y: number;
  label?: string;
}

export default function SimulationPage() {
  const [data1, setData1] = useState<DataPoint[]>([{ x: 0, y: 5 }]);
  const [data2, setData2] = useState<DataPoint[]>([{ x: 0, y: 95 }]);
  const [progress, setProgress] = useState(0);
  const [isPlaying, setIsPlaying] = useState(true);
  const [isDark, setIsDark] = useState(true);

  const duration = 15000; // 15 seconds
  const maxX = 10;
  const maxY1 = 20; // LP Price - upward trend
  const minY2 = -8; // IL Protection - downward trend

  // Graph 1: Upward trending with randomness (always positive, ends high)
  const generateUptrendPath = (points = 50) => {
    const path = [5]; // Start at 5
    let currentY = 5;

    for (let i = 1; i < points; i++) {
      // Calculate progress through the animation
      const progressLocal = i / points;

      // Target value increases toward maxY1
      const targetY = 5 + progressLocal * (maxY1 - 5);

      // Add controlled random variation (±0.8)
      const randomVariation = (Math.random() - 0.5) * 1.6;

      // Combine target movement with randomness
      const change = (targetY - currentY) * 0.15 + randomVariation;
      currentY += change;

      // Keep value in positive range, trending upward
      currentY = Math.max(4, Math.min(currentY, maxY1 * 1.1));
      path.push(currentY);
    }

    // Ensure end value is close to maxY1
    path[points - 1] = maxY1 + (Math.random() - 0.5) * 2;

    // Smooth final approach
    for (let i = Math.floor(points * 0.75); i < points - 1; i++) {
      const smoothProgress = (i - Math.floor(points * 0.75)) / (points - Math.floor(points * 0.75));
      path[i] = path[i] * (1 - smoothProgress * 0.3) + (maxY1 + 1) * smoothProgress * 0.3;
    }

    return path;
  };

  // Graph 2: Downward trending with randomness (ends negative)
  const generateDowntrendPath = (points = 50) => {
    const path = [95]; // Start at 95 (high IL protection)
    let currentY = 95;

    for (let i = 1; i < points; i++) {
      // Calculate progress through the animation
      const progressLocal = i / points;

      // Target value decreases toward minY2
      const targetY = 95 + progressLocal * (minY2 - 95);

      // Add controlled random variation (±2)
      const randomVariation = (Math.random() - 0.5) * 4;

      // Combine target movement with randomness
      const change = (targetY - currentY) * 0.15 + randomVariation;
      currentY += change;

      // Allow negative values but keep reasonable bounds
      currentY = Math.max(minY2 - 5, Math.min(currentY, 100));
      path.push(currentY);
    }

    // Ensure end value is near minY2 (negative)
    path[points - 1] = minY2 + (Math.random() - 0.5) * 3;

    // Smooth final approach to negative
    for (let i = Math.floor(points * 0.75); i < points - 1; i++) {
      const smoothProgress = (i - Math.floor(points * 0.75)) / (points - Math.floor(points * 0.75));
      path[i] = path[i] * (1 - smoothProgress * 0.3) + (minY2 - 1) * smoothProgress * 0.3;
    }

    return path;
  };

  const [path1] = useState(() => generateUptrendPath(50));
  const [path2] = useState(() => generateDowntrendPath(50));

  useEffect(() => {
    if (!isPlaying) return;

    const startTime = Date.now();

    const animate = () => {
      const elapsed = Date.now() - startTime;
      const progressValue = Math.min(elapsed / duration, 1);
      setProgress(progressValue);

      const currentPoint = Math.floor(progressValue * 50);

      // Graph 1: LP Performance (Uptrend)
      const newData1: DataPoint[] = [];
      for (let i = 0; i <= currentPoint; i++) {
        const x = (i / 50) * maxX;
        const y = path1[i];
        newData1.push({
          x: parseFloat(x.toFixed(2)),
          y: parseFloat(y.toFixed(2)),
        });
      }
      setData1(newData1);

      // Graph 2: IL Protection (Downtrend)
      const newData2: DataPoint[] = [];
      for (let i = 0; i <= currentPoint; i++) {
        const x = (i / 50) * maxX;
        const y = path2[i];
        newData2.push({
          x: parseFloat(x.toFixed(2)),
          y: parseFloat(y.toFixed(2)),
        });
      }
      setData2(newData2);

      if (progressValue < 1) {
        requestAnimationFrame(animate);
      }
    };

    animate();
  }, [isPlaying, path1, path2]);

  const handleReset = () => {
    setProgress(0);
    setIsPlaying(true);
    setData1([{ x: 0, y: 5 }]);
    setData2([{ x: 0, y: 95 }]);
  };

  return (
    <div className={`min-h-screen ${isDark ? "bg-gray-900" : "bg-gradient-to-br from-purple-50 to-blue-50"} transition-all duration-500`}>
      {/* Header */}
      <div className={`${isDark ? "bg-gray-800/80 border-gray-700" : "bg-white/80 border-purple-200"} backdrop-blur-xl border-b sticky top-0 z-50`}>
        <div className="max-w-7xl mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center space-x-4">
            <Link href="/" className={`p-2 rounded-lg transition ${isDark ? "hover:bg-gray-700" : "hover:bg-gray-100"}`}>
              <ArrowLeft className="w-6 h-6" />
            </Link>
            <h1 className={`text-2xl font-bold ${isDark ? "text-white" : "text-gray-900"}`}>
              Simulation: LP Performance vs Market Volatility
            </h1>
          </div>
          <button onClick={() => setIsDark(!isDark)} className={`p-2 rounded-lg ${isDark ? "bg-gray-700 hover:bg-gray-600" : "bg-gray-200 hover:bg-gray-300"} transition`}>
            {isDark ? "☀️" : "🌙"}
          </button>
        </div>
      </div>

      {/* Controls */}
      <div className="max-w-7xl mx-auto px-6 py-6">
        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 flex gap-4 items-center border ${isDark ? "border-purple-500/20" : "border-purple-200"}`}>
          <button
            onClick={() => setIsPlaying(!isPlaying)}
            className="bg-gradient-to-r from-purple-600 to-pink-600 hover:shadow-lg hover:shadow-purple-500/50 text-white p-3 rounded-lg transition flex items-center gap-2 font-medium"
          >
            {isPlaying ? (
              <>
                <Pause className="w-5 h-5" />
                Pause
              </>
            ) : (
              <>
                <Play className="w-5 h-5" />
                Play
              </>
            )}
          </button>
          <button
            onClick={handleReset}
            className="bg-gray-600 hover:bg-gray-700 text-white p-3 rounded-lg transition flex items-center gap-2 font-medium"
          >
            <RotateCcw className="w-5 h-5" />
            Reset
          </button>
          <div className="flex-1 bg-gray-700 rounded-full h-3">
            <div
              className="bg-gradient-to-r from-purple-600 to-pink-600 h-3 rounded-full transition-all duration-100 shadow-lg shadow-purple-500/50"
              style={{ width: `${progress * 100}%` }}
            ></div>
          </div>
          <span className={`${isDark ? "text-gray-300" : "text-gray-700"} font-mono text-lg font-bold`}>
            {(progress * 100).toFixed(0)}%
          </span>
        </div>
      </div>

      {/* Charts */}
      <div className="max-w-7xl mx-auto px-6 pb-12 grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Chart 1: LP Price Movement - UPTREND */}
        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 border ${isDark ? "border-purple-500/30" : "border-purple-200"} shadow-lg`}>
          <div className="mb-6">
            <h2 className={`text-xl font-bold ${isDark ? "text-white" : "text-gray-900"}`}>
              📈 Hedged LP Position Value
            </h2>
            <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"} mt-1`}>
              With automatic hedging enabled - Protected from IL
            </p>
            <div className="mt-3 flex justify-between items-center">
              <span className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"}`}>
                Current: ${(data1[data1.length - 1]?.y * 300 || 0).toFixed(2)}
              </span>
              <span className="text-green-500 font-bold text-lg">
                ↑ +{((data1[data1.length - 1]?.y || 5) - 5).toFixed(1)}%
              </span>
            </div>
          </div>
          <ResponsiveContainer width="100%" height={320}>
            <LineChart data={data1}>
              <CartesianGrid strokeDasharray="3 3" stroke={isDark ? "#374151" : "#e5e7eb"} />
              <XAxis dataKey="x" stroke={isDark ? "#9ca3af" : "#6b7280"} label={{ value: "Time (seconds)", position: "insideBottomRight", offset: -5 }} />
              <YAxis stroke={isDark ? "#9ca3af" : "#6b7280"} label={{ value: "Value ($)", angle: -90, position: "insideLeft" }} />
              <Tooltip
                contentStyle={{
                  backgroundColor: isDark ? "#1f2937" : "#ffffff",
                  border: `2px solid #a855f7`,
                  borderRadius: "8px",
                  color: isDark ? "#f3f4f6" : "#111827",
                  padding: "12px",
                }}
                formatter={(value: any) => [`$${(value * 300).toFixed(2)}`, "LP Value"]}
              />
              <Line
                type="monotone"
                dataKey="y"
                stroke="#a855f7"
                strokeWidth={4}
                dot={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
          <div className={`mt-4 pt-4 border-t ${isDark ? "border-gray-700" : "border-purple-200"}`}>
            <p className={`text-xs ${isDark ? "text-gray-400" : "text-gray-600"}`}>
              ✓ LP earns trading fees while hedge protects from price divergence loss
            </p>
          </div>
        </div>

        {/* Chart 2: IL Protection - DOWNTREND */}
        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 border ${isDark ? "border-red-500/30" : "border-red-200"} shadow-lg`}>
          <div className="mb-6">
            <h2 className={`text-xl font-bold ${isDark ? "text-white" : "text-gray-900"}`}>
              📉 Unhedged LP Position Value
            </h2>
            <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"} mt-1`}>
              Without hedging - Exposed to impermanent loss
            </p>
            <div className="mt-3 flex justify-between items-center">
              <span className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"}`}>
                Current: ${Math.max(0, data2[data2.length - 1]?.y * 150 || 0).toFixed(2)}
              </span>
              <span className="text-red-500 font-bold text-lg">
                ↓ {data2[data2.length - 1]?.y.toFixed(1) || 95}%
              </span>
            </div>
          </div>
          <ResponsiveContainer width="100%" height={320}>
            <LineChart data={data2}>
              <CartesianGrid strokeDasharray="3 3" stroke={isDark ? "#374151" : "#e5e7eb"} />
              <XAxis dataKey="x" stroke={isDark ? "#9ca3af" : "#6b7280"} label={{ value: "Time (seconds)", position: "insideBottomRight", offset: -5 }} />
              <YAxis stroke={isDark ? "#9ca3af" : "#6b7280"} label={{ value: "IL Loss (%)", angle: -90, position: "insideLeft" }} />
              <Tooltip
                contentStyle={{
                  backgroundColor: isDark ? "#1f2937" : "#ffffff",
                  border: `2px solid #ef4444`,
                  borderRadius: "8px",
                  color: isDark ? "#f3f4f6" : "#111827",
                  padding: "12px",
                }}
                formatter={(value: any) => {
                  const val = value as number;
                  return [`${val.toFixed(2)}% Loss`, "IL"];
                }}
              />
              <Line
                type="monotone"
                dataKey="y"
                stroke="#ef4444"
                strokeWidth={4}
                dot={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
          <div className={`mt-4 pt-4 border-t ${isDark ? "border-gray-700" : "border-red-200"}`}>
            <p className={`text-xs ${isDark ? "text-gray-400" : "text-gray-600"}`}>
              ✗ Without hedge, LP suffers significant IL as market becomes volatile
            </p>
          </div>
        </div>
      </div>

      {/* Comparison Stats */}
      <div className="max-w-7xl mx-auto px-6 pb-12 grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 border ${isDark ? "border-purple-500/20" : "border-purple-200"}`}>
          <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"} mb-2`}>
            Hedged LP Position
          </p>
          <p className="text-3xl font-bold text-purple-500">
            ${(data1[data1.length - 1]?.y * 300 || 0).toFixed(0)}
          </p>
          <p className="text-xs text-green-500 mt-2 font-bold">
            ↑ Protected & Growing
          </p>
        </div>

        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 border ${isDark ? "border-red-500/20" : "border-red-200"}`}>
          <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"} mb-2`}>
            Unhedged LP Position
          </p>
          <p className="text-3xl font-bold text-red-500">
            ${Math.max(0, data2[data2.length - 1]?.y * 150 || 0).toFixed(0)}
          </p>
          <p className="text-xs text-red-500 mt-2 font-bold">
            ↓ {Math.abs(data2[data2.length - 1]?.y || 95).toFixed(0)}% Loss
          </p>
        </div>

        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-6 border ${isDark ? "border-green-500/20" : "border-green-200"}`}>
          <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"} mb-2`}>
            Hedge Protection Saved
          </p>
          <p className="text-3xl font-bold text-green-500">
            ${(Math.max(0, data2[data2.length - 1]?.y * 150 || 0) + (data1[data1.length - 1]?.y * 300 || 0)).toFixed(0)}
          </p>
          <p className="text-xs text-green-500 mt-2 font-bold">
            ✓ Protected Capital
          </p>
        </div>
      </div>

      {/* Info */}
      <div className="max-w-7xl mx-auto px-6 pb-12">
        <div className={`${isDark ? "bg-gray-800" : "bg-white"} rounded-lg p-8 border ${isDark ? "border-purple-500/20" : "border-purple-200"}`}>
          <h3 className={`text-2xl font-bold mb-6 ${isDark ? "text-white" : "text-gray-900"}`}>
            Understanding the Simulation
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="p-4 rounded-lg bg-gradient-to-br from-purple-500/10 to-pink-500/10 border border-purple-500/20">
              <h4 className={`font-bold mb-3 text-lg ${isDark ? "text-purple-400" : "text-purple-600"}`}>
                📈 Left Chart: Hedged LP (GAINS)
              </h4>
              <ul className={`space-y-2 text-sm ${isDark ? "text-gray-300" : "text-gray-700"}`}>
                <li>✓ 79% allocated to Uniswap V3 LP earning fees</li>
                <li>✓ 21% allocated to Aave short hedge</li>
                <li>✓ Net result: Always positive, trending upward</li>
                <li>✓ Protection maintained against IL</li>
              </ul>
            </div>

            <div className="p-4 rounded-lg bg-gradient-to-br from-red-500/10 to-orange-500/10 border border-red-500/20">
              <h4 className={`font-bold mb-3 text-lg ${isDark ? "text-red-400" : "text-red-600"}`}>
                📉 Right Chart: Unhedged LP (LOSSES)
              </h4>
              <ul className={`space-y-2 text-sm ${isDark ? "text-gray-300" : "text-gray-700"}`}>
                <li>✗ 100% exposed to market volatility</li>
                <li>✗ Subject to significant impermanent loss</li>
                <li>✗ Downward trend as market changes</li>
                <li>✗ Can end in negative territory</li>
              </ul>
            </div>
          </div>

          <div className="mt-6 pt-6 border-t border-gray-600">
            <p className={`text-sm ${isDark ? "text-gray-400" : "text-gray-600"}`}>
              💡 <strong>Key Insight:</strong> This 15-second simulation shows why hedging matters. On the left, your position grows steadily with automated protection. On the right, an unhedged LP suffers progressive losses from impermanent loss as prices diverge. HedgeCraft's intelligent 79/21 split keeps you earning while staying protected!
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
