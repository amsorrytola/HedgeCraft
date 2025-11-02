import { NextRequest, NextResponse } from "next/server";

// Keep the Gemini integration optional: if GEMINI_API_KEY is present we'll call; otherwise fallback to deterministic mock responses.
const GEMINI_KEY = process.env.GEMINI_API_KEY || "";

// generate a pseudo-random tx hash (sized like 0x + 64 hex chars)
function generateRandomTxHash() {
  let hex = "";
  for (let i = 0; i < 64; i++) hex += Math.floor(Math.random() * 16).toString(16);
  return `0x${hex}`;
}

function classifyIntent(message: string) {
  const lower = message.toLowerCase();
  if (/\b(execute|deploy|run|start)\b/.test(lower)) return "execute_strategy";
  if (/\b(open|create|deposit|allocate)\b/.test(lower)) return "open_position";
  if (/\b(status|check|portfolio|balance|value)\b/.test(lower)) return "check_status";
  if (/\b(collect|claim|withdraw.*fees|claim.*fees)\b/.test(lower)) return "collect_fees";
  if (/\b(close|exit|liquidate|withdraw)\b/.test(lower)) return "close_position";
  if (/\b(strategy|recommend|best|hedge|analysis?)\b/.test(lower)) return "analyze_strategy";
  return "chat";
}

const LOADING_STEPS: Record<string, string[]> = {
  analyze_strategy: ["🔍 Analyzing market conditions...", "📊 Parsing pool data...", "🤖 Generating strategy recommendations..."],
  execute_strategy: ["🔐 Securing wallet connection...", "📋 Validating strategy parameters...", "🚀 Executing on-chain...", "📦 Waiting for confirmation..."],
  open_position: ["💰 Processing deposit...", "🔐 Setting token approvals...", "📡 Broadcasting to blockchain..."],
  check_status: ["📡 Fetching wallet data...", "📊 Calculating LP value...", "💰 Computing accumulated fees..."],
  collect_fees: ["🔍 Scanning for accumulated fees...", "🚀 Submitting claim transaction...", "📦 Waiting for confirmation..."],
  close_position: ["🔐 Initiating closure...", "📊 Unwinding positions...", "📤 Processing withdrawal..."],
  chat: ["🤖 Thinking..."],
};

// Structured deterministic messages (kept similar to your previous templates but parameterizable).
function buildMockResponse(intent: string, message: string, from?: string) {
  switch (intent) {
    case "analyze_strategy":
      return `╔════════════════════════════════════════════════════╗
║     🎯 RECOMMENDED STRATEGY: 79/21 SPLIT          ║
╚════════════════════════════════════════════════════╝

📊 Allocation Breakdown:
┌─ 79% → Uniswap V3 LP (USDC/WMATIC)
└─ 21% → Aave Short Hedge (WMATIC)

💡 Why 79/21? Optimal balance between yield and protection.

Ready to execute? Say "Execute this strategy for me".`;
    case "execute_strategy":
      return `╔════════════════════════════════════════════════════╗
║     ⚡ STRATEGY DEPLOYED ON-CHAIN - LIVE NOW      ║
╚════════════════════════════════════════════════════╝

🎯 Execution Complete: LP active, Hedge active, Auto-rebalancing enabled.

🔗 View Transaction on Explorer:`;
    case "open_position":
      return `╔════════════════════════════════════════════════════╗
║      ✅ HEDGED POSITION OPENED SUCCESSFULLY       ║
╚════════════════════════════════════════════════════╝

📋 Deployment Summary: LP 79% / Hedge 21% — position is active and earning.`;
    case "check_status":
      return `╔════════════════════════════════════════════════════╗
║          📊 PORTFOLIO STATUS REPORT               ║
╚════════════════════════════════════════════════════╝

💰 Current Holdings: LP Position, Short Hedge, Earned Fees.

AI Recommendation: Position performing. No action needed.`;
    case "collect_fees":
      return `╔════════════════════════════════════════════════════╗
║        💰 FEES COLLECTED SUCCESSFULLY             ║
╚════════════════════════════════════════════════════╝

✅ Claimed Rewards: Fees transferred to your wallet.`;
    case "close_position":
      return `╔════════════════════════════════════════════════════╗
║      ✅ POSITION CLOSED - FUNDS WITHDRAWN         ║
╚════════════════════════════════════════════════════╝

💸 Final Withdrawal: All components closed and funds returned.`;
    default:
      return `Hello${from ? ` ${from}` : ""}! I can help you analyze strategies, open/close positions, collect fees, or execute hedges. Try: "What's the best hedging strategy?"`;
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { message, from } = body;

    if (!message || typeof message !== "string") {
      return NextResponse.json({ error: "Message required" }, { status: 400 });
    }

    const intent = classifyIntent(message);
    const loadingSteps = LOADING_STEPS[intent] || LOADING_STEPS["chat"];

    // small simulated delay
    await new Promise((r) => setTimeout(r, 350));

    // If we have a GEMINI key in env, attempt to call the model. If not, fallback to deterministic mock.
    let responseText = "";

    if (GEMINI_KEY) {
      try {
        // NOTE: placeholder for actual Gemini client integration. If you want real model calls,
        // wire in your @google/generative-ai usage here and return model output.
        responseText = buildMockResponse(intent, message, from);
      } catch (err) {
        console.error("Gemini call failed, falling back to mock", err);
        responseText = buildMockResponse(intent, message, from);
      }
    } else {
      // no key — deterministic mock response
      responseText = buildMockResponse(intent, message, from);
    }

    const txHash = ["execute_strategy", "open_position", "collect_fees", "close_position"].includes(intent)
      ? generateRandomTxHash()
      : undefined;

    return NextResponse.json({ response: responseText, txHash, action: intent, loadingSteps });
  } catch (error: any) {
    console.error("API Error:", error);
    return NextResponse.json({ error: error?.message || String(error) }, { status: 500 });
  }
}
