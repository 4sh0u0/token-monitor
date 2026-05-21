'use strict';

const { Client } = require('@xhayper/discord-rpc');

const CLIENT_ID = '1507034330436862062';
const GITHUB_URL = 'https://github.com/Javis603/token-monitor';
const KNOWN_CLIENT_ASSETS = new Set([
  'claude', 'codex', 'hermes', 'gemini', 'cursor', 'opencode', 'openclaw'
]);
const CLIENT_LABELS = {
  claude: 'Claude', codex: 'Codex', hermes: 'Hermes',
  gemini: 'Gemini', cursor: 'Cursor', opencode: 'OpenCode', openclaw: 'OpenClaw'
};
const UPDATE_MIN_INTERVAL_MS = 15000;
const RECONNECT_DELAY_MS = 30000;

let client = null;
let isConnected = false;
let startTimestamp = 0;
let latestStats = null;
let pendingPayload = null;
let lastSentAt = 0;
let flushTimer = null;
let reconnectTimer = null;
let stopped = true;

function formatCost(value) {
  const amount = Number(value || 0);
  return `$${amount.toFixed(amount >= 10 ? 2 : 4)}`;
}

function formatTokensCompact(value) {
  const n = Math.round(Number(value || 0));
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace(/\.0$/, '')}K`;
  return String(n);
}

function topClient(today) {
  const entries = Object.entries(today?.clients || {})
    .filter(([, v]) => Number(v) > 0)
    .sort((a, b) => Number(b[1]) - Number(a[1]));
  return entries[0]?.[0] || null;
}

function buildPayload(stats) {
  const today = stats?.periods?.today || { totalTokens: 0, costUsd: 0, clients: {} };
  const totalTokens = Number(today.totalTokens || 0);
  const base = {
    type: 0,
    largeImageKey: 'logo',
    largeImageText: 'Token Monitor',
    startTimestamp,
    buttons: [{ label: 'View on GitHub', url: GITHUB_URL }]
  };
  if (totalTokens === 0) {
    return { ...base, details: 'Token Monitor', state: 'No usage today' };
  }
  const top = topClient(today);
  const label = (top && CLIENT_LABELS[top]) || (top ? top : 'Active');
  const payload = {
    ...base,
    details: `${label} · ${formatTokensCompact(totalTokens)} tokens`,
    state: `${formatCost(today.costUsd)} today`
  };
  if (top && KNOWN_CLIENT_ASSETS.has(top)) {
    payload.smallImageKey = top;
    payload.smallImageText = label;
  }
  return payload;
}

function flush() {
  flushTimer = null;
  if (!isConnected || !pendingPayload) return;
  lastSentAt = Date.now();
  const payload = pendingPayload;
  pendingPayload = null;
  client.user?.setActivity(payload).catch((error) => {
    console.log(`[discord-rpc] setActivity failed: ${error.message}`);
  });
}

function scheduleFlush() {
  if (!isConnected || !pendingPayload) return;
  const wait = Math.max(0, UPDATE_MIN_INTERVAL_MS - (Date.now() - lastSentAt));
  if (wait === 0) { flush(); return; }
  if (flushTimer) return;
  flushTimer = setTimeout(flush, wait);
}

function scheduleReconnect() {
  if (stopped || reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, RECONNECT_DELAY_MS);
}

function connect() {
  if (stopped || client) return;
  client = new Client({ clientId: CLIENT_ID });
  client.on('ready', () => {
    isConnected = true;
    startTimestamp = Date.now();
    pendingPayload = buildPayload(latestStats);
    flush();
  });
  client.on('disconnected', () => {
    isConnected = false;
    try { client?.destroy?.(); } catch (_) {}
    client = null;
    if (flushTimer) { clearTimeout(flushTimer); flushTimer = null; }
    scheduleReconnect();
  });
  client.login().catch((error) => {
    console.log(`[discord-rpc] connect failed: ${error.message}`);
    try { client?.destroy?.(); } catch (_) {}
    client = null;
    scheduleReconnect();
  });
}

function startDiscordRpc() {
  if (!stopped) return;
  stopped = false;
  connect();
}

function stopDiscordRpc() {
  stopped = true;
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  if (flushTimer) { clearTimeout(flushTimer); flushTimer = null; }
  pendingPayload = null;
  lastSentAt = 0;
  startTimestamp = 0;
  if (client) {
    try { client.user?.clearActivity?.(); } catch (_) {}
    try { client.destroy(); } catch (_) {}
  }
  client = null;
  isConnected = false;
}

function updateDiscordRpc(stats) {
  latestStats = stats;
  if (stopped) return;
  pendingPayload = buildPayload(stats);
  scheduleFlush();
}

module.exports = { startDiscordRpc, stopDiscordRpc, updateDiscordRpc };
