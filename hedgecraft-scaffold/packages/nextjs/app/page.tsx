"use client";

import React from "react";
import Link from "next/link";
import { useAccount } from "wagmi";
import {
  Sparkles,
  TrendingUp,
  Shield,
  Zap,
  ArrowRight,
  CheckCircle,
} from "lucide-react";
import { Address } from "~~/components/scaffold-eth";

const Home = () => {
  const { address: connectedAddress } = useAccount();

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-gray-900 text-white overflow-hidden">
      {/* Animated background blobs */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-purple-500 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob"></div>
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-blue-500 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob animation-delay-2000"></div>
        <div className="absolute top-40 left-40 w-80 h-80 bg-pink-500 rounded-full mix-blend-multiply filter blur-3xl opacity-20 animate-blob animation-delay-4000"></div>
      </div>

      {/* Navigation */}
      <nav className="relative z-10 backdrop-blur-xl bg-gray-900/80 border-b border-purple-500/20 sticky top-0">
        <div className="max-w-7xl mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 bg-gradient-to-br from-purple-500 to-pink-500 rounded-lg flex items-center justify-center">
              <Sparkles className="w-6 h-6 text-white" />
            </div>
            <h1 className="text-2xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
              HedgeCraft
            </h1>
            <span className="text-xs px-3 py-1 rounded-full bg-purple-500/20 text-purple-300 border border-purple-500/30">
              AI-Powered LP Hedging
            </span>
          </div>
          {connectedAddress && (
            <div className="text-sm text-gray-400">
              Connected: <Address address={connectedAddress} />
            </div>
          )}
        </div>
      </nav>

      {/* Main Content */}
      <div className="relative z-10 max-w-7xl mx-auto px-6 py-16">
        {/* Hero Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center mb-20">
          {/* Left */}
          <div>
            <h2 className="text-5xl font-bold mb-6 leading-tight">
              Protect Your <span className="bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">Liquidity</span>
            </h2>
            <p className="text-xl text-gray-300 mb-8 leading-relaxed">
              Earn yield on Uniswap V3 while staying hedged against impermanent loss. AI-powered automation handles everything for you.
            </p>

            {/* Stats */}
            <div className="grid grid-cols-3 gap-4 mb-8">
              <div className="p-4 bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl">
                <p className="text-sm text-gray-400">IL Protection</p>
                <p className="text-2xl font-bold text-purple-400">90%+</p>
              </div>
              <div className="p-4 bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl">
                <p className="text-sm text-gray-400">Gas Fees</p>
                <p className="text-2xl font-bold text-purple-400">~$0.01</p>
              </div>
              <div className="p-4 bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl">
                <p className="text-sm text-gray-400">Non-Custodial</p>
                <p className="text-2xl font-bold text-purple-400">100%</p>
              </div>
            </div>

            {/* Features */}
            <div className="space-y-3 mb-8">
              <div className="flex items-center space-x-3">
                <CheckCircle className="w-5 h-5 text-green-400" />
                <span>Automated LP + Short Hedging</span>
              </div>
              <div className="flex items-center space-x-3">
                <CheckCircle className="w-5 h-5 text-green-400" />
                <span>AI-Powered Chat Agent</span>
              </div>
              <div className="flex items-center space-x-3">
                <CheckCircle className="w-5 h-5 text-green-400" />
                <span>Powered by Uniswap V3 & Aave</span>
              </div>
            </div>

            {/* CTA Buttons */}
            <div className="flex flex-col sm:flex-row gap-4">
              <Link
                href="/chat"
                className="bg-gradient-to-r from-purple-600 to-pink-600 text-white px-8 py-4 rounded-lg font-semibold hover:shadow-lg hover:shadow-purple-500/50 transition flex items-center justify-center space-x-2 group"
              >
                <span>Launch Agent</span>
                <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition" />
              </Link>
              <Link
                href="/simulation"
                className="px-8 py-4 rounded-lg font-semibold border border-purple-500 text-purple-400 hover:bg-purple-500/10 transition"
              >
                Simulation
              </Link>
            </div>
          </div>

          {/* Right - Feature Card */}
          <div className="relative">
            <div className="absolute inset-0 bg-gradient-to-r from-purple-600 to-pink-600 rounded-2xl blur-xl opacity-20"></div>
            <div className="relative bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-2xl p-8">
              <h3 className="text-2xl font-bold mb-4">How It Works</h3>
              <div className="space-y-4">
                <div className="flex gap-4">
                  <div className="flex-shrink-0">
                    <div className="flex items-center justify-center h-10 w-10 rounded-md bg-purple-600">
                      <span className="text-white font-bold">1</span>
                    </div>
                  </div>
                  <div>
                    <h4 className="font-semibold">Deposit Assets</h4>
                    <p className="text-gray-400 text-sm">Connect wallet and deposit your tokens</p>
                  </div>
                </div>
                <div className="flex gap-4">
                  <div className="flex-shrink-0">
                    <div className="flex items-center justify-center h-10 w-10 rounded-md bg-purple-600">
                      <span className="text-white font-bold">2</span>
                    </div>
                  </div>
                  <div>
                    <h4 className="font-semibold">Auto Allocation</h4>
                    <p className="text-gray-400 text-sm">79% LP + 21% Short Hedge automatically</p>
                  </div>
                </div>
                <div className="flex gap-4">
                  <div className="flex-shrink-0">
                    <div className="flex items-center justify-center h-10 w-10 rounded-md bg-purple-600">
                      <span className="text-white font-bold">3</span>
                    </div>
                  </div>
                  <div>
                    <h4 className="font-semibold">Earn & Protect</h4>
                    <p className="text-gray-400 text-sm">Get yield while protected from IL</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Benefits Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-20">
          <div className="bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl p-8 hover:border-purple-500/50 transition">
            <TrendingUp className="w-12 h-12 text-purple-400 mb-4" />
            <h3 className="text-xl font-bold mb-2">90% IL Protection</h3>
            <p className="text-gray-400">
              Automatically hedges your LP exposure reducing impermanent loss by over 90%
            </p>
          </div>
          <div className="bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl p-8 hover:border-purple-500/50 transition">
            <Zap className="w-12 h-12 text-purple-400 mb-4" />
            <h3 className="text-xl font-bold mb-2">Ultra-Low Gas</h3>
            <p className="text-gray-400">
              Deployed on Polygon with transaction costs under $0.01 per operation
            </p>
          </div>
          <div className="bg-gray-800/50 backdrop-blur border border-purple-500/20 rounded-xl p-8 hover:border-purple-500/50 transition">
            <Shield className="w-12 h-12 text-purple-400 mb-4" />
            <h3 className="text-xl font-bold mb-2">Non-Custodial</h3>
            <p className="text-gray-400">
              You control your keys and funds. Smart contracts execute without middlemen
            </p>
          </div>
        </div>

        {/* Footer CTA */}
        <div className="text-center">
          <p className="text-gray-400 mb-6">Ready to get started?</p>
          <Link
            href="/chat"
            className="inline-block bg-gradient-to-r from-purple-600 to-pink-600 text-white px-12 py-4 rounded-lg font-semibold hover:shadow-lg hover:shadow-purple-500/50 transition"
          >
            Open HedgeCraft Agent Now
          </Link>
        </div>
      </div>

      {/* Tailwind animations */}
      <style jsx>{`
        @keyframes blob {
          0% {
            transform: translate(0px, 0px) scale(1);
          }
          33% {
            transform: translate(30px, -50px) scale(1.1);
          }
          66% {
            transform: translate(-20px, 20px) scale(0.9);
          }
          100% {
            transform: translate(0px, 0px) scale(1);
          }
        }
        .animate-blob {
          animation: blob 7s infinite;
        }
        .animation-delay-2000 {
          animation-delay: 2s;
        }
        .animation-delay-4000 {
          animation-delay: 4s;
        }
      `}</style>
    </div>
  );
};

export default Home;

