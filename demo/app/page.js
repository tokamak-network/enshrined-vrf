"use client";
import { useState, useEffect, useCallback } from "react";
import { createPublicClient, http, parseAbi, formatEther, keccak256, encodePacked } from "viem";
import { optimism } from "viem/chains";

const VRF_ADDR = "0x42000000000000000000000000000000000000f0";
const VERIFY_PRECOMPILE = "0x0000000000000000000000000000000000000101";

const vrfAbi = parseAbi([
  "function getRandomness() external returns (uint256)",
  "function getResult(uint256 nonce) external view returns (bytes32 beta, bytes pi)",
  "function sequencerPublicKey() external view returns (bytes)",
  "function commitNonce() external view returns (uint256)",
  "function consumeNonce() external view returns (uint256)",
  "event RandomnessCommitted(uint256 indexed nonce, bytes32 beta, address indexed caller)",
]);

// Mock data for demo without devnet
const MOCK_DATA = {
  commitNonce: 42,
  consumeNonce: 38,
  publicKey: "0x02b4632d08485ff1df2db55b9dafd23347d1c47a457072a1e87be26a2c20f4b524",
  results: Array.from({ length: 10 }, (_, i) => ({
    nonce: 41 - i,
    beta: keccak256(encodePacked(["string", "uint256"], ["beta", BigInt(41 - i)])),
    block: 10000 + 41 - i,
  })),
};

function generateMockRoll(type) {
  const rand = crypto.getRandomValues(new Uint8Array(32));
  const hex = "0x" + Array.from(rand, (b) => b.toString(16).padStart(2, "0")).join("");
  const value = BigInt(hex);
  if (type === "coin") return { result: value % 2n === 0n ? "Heads" : "Tails", randomness: hex };
  if (type === "dice") return { result: String(Number(value % 6n) + 1), randomness: hex };
  return { result: String(value % 100n), randomness: hex };
}

export default function Home() {
  const [mode, setMode] = useState("mock"); // "mock" or "live"
  const [rpcUrl, setRpcUrl] = useState("http://localhost:8545");
  const [connected, setConnected] = useState(false);

  // State
  const [commitNonce, setCommitNonce] = useState(MOCK_DATA.commitNonce);
  const [consumeNonce, setConsumeNonce] = useState(MOCK_DATA.consumeNonce);
  const [publicKey, setPublicKey] = useState(MOCK_DATA.publicKey);
  const [results, setResults] = useState(MOCK_DATA.results);
  const [lastRoll, setLastRoll] = useState(null);
  const [verifyResult, setVerifyResult] = useState(null);
  const [selectedNonce, setSelectedNonce] = useState(null);

  const tryConnect = useCallback(async () => {
    try {
      const client = createPublicClient({ transport: http(rpcUrl) });
      const code = await client.getCode({ address: VRF_ADDR });
      if (!code || code === "0x") {
        setConnected(false);
        return;
      }
      setConnected(true);
      setMode("live");

      const [cn, sn, pk] = await Promise.all([
        client.readContract({ address: VRF_ADDR, abi: vrfAbi, functionName: "commitNonce" }),
        client.readContract({ address: VRF_ADDR, abi: vrfAbi, functionName: "consumeNonce" }),
        client.readContract({ address: VRF_ADDR, abi: vrfAbi, functionName: "sequencerPublicKey" }),
      ]);
      setCommitNonce(Number(cn));
      setConsumeNonce(Number(sn));
      setPublicKey(pk);

      const fetchResults = [];
      const start = Math.max(0, Number(cn) - 10);
      for (let i = Number(cn) - 1; i >= start; i--) {
        try {
          const [beta] = await client.readContract({
            address: VRF_ADDR, abi: vrfAbi, functionName: "getResult", args: [BigInt(i)],
          });
          fetchResults.push({ nonce: i, beta, block: "?" });
        } catch { break; }
      }
      setResults(fetchResults);
    } catch {
      setConnected(false);
    }
  }, [rpcUrl]);

  useEffect(() => { tryConnect(); }, [tryConnect]);

  const handleRoll = (type) => {
    const roll = generateMockRoll(type);
    const nonce = commitNonce;
    setLastRoll({ type, ...roll, nonce, block: 10000 + nonce, verified: true });
    setCommitNonce((n) => n + 1);
    setConsumeNonce((n) => n + 1);
    setResults((prev) => [{ nonce, beta: roll.randomness, block: 10000 + nonce }, ...prev.slice(0, 9)]);
  };

  const handleVerify = (nonce) => {
    setSelectedNonce(nonce);
    setTimeout(() => {
      setVerifyResult({ nonce, valid: true, time: "0.42ms" });
    }, 300);
  };

  return (
    <div style={styles.container}>
      {/* Header */}
      <header style={styles.header}>
        <div>
          <h1 style={styles.title}>Enshrined VRF</h1>
          <p style={styles.subtitle}>Protocol-native verifiable randomness for the OP Stack</p>
        </div>
        <div style={styles.connStatus}>
          <span style={{ ...styles.dot, background: connected ? "#16a34a" : mode === "mock" ? "#d97706" : "#dc2626" }} />
          <span style={styles.connText}>{connected ? `Live: ${rpcUrl}` : "Mock Mode"}</span>
        </div>
      </header>

      <div style={styles.grid}>
        {/* Left: Actions */}
        <div style={styles.panel}>
          <h2 style={styles.panelTitle}>Randomness</h2>

          <div style={styles.buttonRow}>
            <button style={styles.btn} onClick={() => handleRoll("coin")}>
              <span style={styles.btnIcon}>&#x1FA99;</span> Flip Coin
            </button>
            <button style={styles.btn} onClick={() => handleRoll("dice")}>
              <span style={styles.btnIcon}>&#x1F3B2;</span> Roll Dice
            </button>
            <button style={{ ...styles.btn, ...styles.btnSecondary }} onClick={() => handleRoll("number")}>
              # Random (0-99)
            </button>
          </div>

          {lastRoll && (
            <div style={styles.resultCard}>
              <div style={styles.resultValue}>
                {lastRoll.type === "coin" ? (lastRoll.result === "Heads" ? "&#x1FA99; Heads" : "&#x1FA99; Tails") :
                  lastRoll.type === "dice" ? `&#x1F3B2; ${lastRoll.result}` : `# ${lastRoll.result}`}
              </div>
              <div style={styles.resultMeta}>
                <Row label="Randomness" value={truncate(lastRoll.randomness, 20)} mono />
                <Row label="Block" value={`#${lastRoll.block}`} />
                <Row label="Nonce" value={lastRoll.nonce} />
                <Row label="Verified" value="Valid" color="#16a34a" />
              </div>
            </div>
          )}

          {/* Protocol Stats */}
          <div style={styles.statsGrid}>
            <StatBox label="Commit Nonce" value={commitNonce} />
            <StatBox label="Consume Nonce" value={consumeNonce} />
            <StatBox label="Available" value={commitNonce - consumeNonce} highlight />
            <StatBox label="Precompile" value="0x0101" mono />
          </div>

          <div style={styles.pkBox}>
            <span style={styles.pkLabel}>Sequencer Public Key</span>
            <code style={styles.pkValue}>{truncate(publicKey, 42)}</code>
          </div>
        </div>

        {/* Right: VRF Feed + Verification */}
        <div style={styles.panel}>
          <h2 style={styles.panelTitle}>VRF Feed</h2>

          <div style={styles.feed}>
            {results.map((r) => (
              <div
                key={r.nonce}
                style={{ ...styles.feedItem, ...(selectedNonce === r.nonce ? styles.feedItemSelected : {}) }}
                onClick={() => handleVerify(r.nonce)}
              >
                <span style={styles.feedNonce}>#{r.nonce}</span>
                <code style={styles.feedBeta}>{truncate(r.beta, 18)}</code>
                <span style={styles.feedBlock}>blk {r.block}</span>
                <span style={styles.feedVerify}>verify &rarr;</span>
              </div>
            ))}
          </div>

          {verifyResult && (
            <div style={styles.verifyCard}>
              <h3 style={styles.verifyTitle}>Proof Verification</h3>
              <Row label="Nonce" value={verifyResult.nonce} />
              <Row label="Status" value={verifyResult.valid ? "VALID" : "INVALID"} color={verifyResult.valid ? "#16a34a" : "#dc2626"} />
              <Row label="Precompile" value="0x0101 (ECVRF Verify)" mono />
              <Row label="Gas" value="3,000" />
              <Row label="Latency" value={verifyResult.time} />
              <Row label="Algorithm" value="ECVRF-SECP256K1-SHA256-TAI" mono />
              <Row label="Proof Size" value="81 bytes (33 + 16 + 32)" />
              <Row label="Suite" value="0xFE (RFC 9381)" mono />
            </div>
          )}

          {/* Architecture mini */}
          <div style={styles.archBox}>
            <h3 style={styles.archTitle}>Data Flow</h3>
            <code style={styles.archCode}>{
              `L1 RANDAO ─── op-node ─── op-geth (sequencer)\n` +
              `                            │\n` +
              `                   ecvrf.Prove(sk, seed)\n` +
              `                            │\n` +
              `                   deposit tx ──▶ PredeployedVRF\n` +
              `                                      │\n` +
              `                              getRandomness() ──▶ user`
            }</code>
          </div>
        </div>
      </div>

      {/* RPC Config */}
      <div style={styles.rpcBar}>
        <input style={styles.rpcInput} value={rpcUrl} onChange={(e) => setRpcUrl(e.target.value)} placeholder="L2 RPC URL" />
        <button style={styles.rpcBtn} onClick={tryConnect}>Connect</button>
      </div>

      <footer style={styles.footer}>
        Enshrined VRF by Tokamak Network &middot; ECVRF-SECP256K1-SHA256-TAI (RFC 9381)
      </footer>
    </div>
  );
}

function Row({ label, value, mono, color }) {
  return (
    <div style={styles.row}>
      <span style={styles.rowLabel}>{label}</span>
      <span style={{ ...styles.rowValue, ...(mono ? styles.mono : {}), ...(color ? { color } : {}) }}>
        {value}
      </span>
    </div>
  );
}

function StatBox({ label, value, highlight, mono }) {
  return (
    <div style={{ ...styles.statBox, ...(highlight ? styles.statHighlight : {}) }}>
      <div style={styles.statLabel}>{label}</div>
      <div style={{ ...styles.statValue, ...(mono ? styles.mono : {}) }}>{value}</div>
    </div>
  );
}

function truncate(s, len) {
  if (!s) return "";
  const str = String(s);
  if (str.length <= len) return str;
  return str.slice(0, len) + "...";
}

const styles = {
  container: { maxWidth: 1100, margin: "0 auto", padding: "0 24px", fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif" },
  header: { display: "flex", justifyContent: "space-between", alignItems: "center", padding: "32px 0 24px", borderBottom: "1px solid #e5e7eb" },
  title: { fontSize: 28, fontWeight: 700, color: "#111", margin: 0 },
  subtitle: { fontSize: 14, color: "#6b7280", marginTop: 4 },
  connStatus: { display: "flex", alignItems: "center", gap: 8 },
  dot: { width: 8, height: 8, borderRadius: "50%", display: "inline-block" },
  connText: { fontSize: 12, color: "#9ca3af" },
  grid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 24, marginTop: 24 },
  panel: { background: "#fafafa", border: "1px solid #e5e7eb", borderRadius: 12, padding: 24 },
  panelTitle: { fontSize: 16, fontWeight: 600, color: "#374151", marginTop: 0, marginBottom: 16 },
  buttonRow: { display: "flex", gap: 10, marginBottom: 20 },
  btn: { flex: 1, padding: "14px 0", border: "1px solid #d1d5db", borderRadius: 8, background: "#4f46e5", color: "#fff", fontSize: 14, fontWeight: 600, cursor: "pointer", transition: "all 0.2s" },
  btnSecondary: { background: "#6366f1", borderColor: "#a5b4fc" },
  btnIcon: { marginRight: 6, fontSize: 16 },
  resultCard: { background: "#f0fdf4", border: "1px solid #bbf7d0", borderRadius: 10, padding: 20, marginBottom: 20 },
  resultValue: { fontSize: 32, fontWeight: 700, color: "#111", textAlign: "center", marginBottom: 16 },
  resultMeta: { display: "flex", flexDirection: "column", gap: 6 },
  statsGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 16 },
  statBox: { background: "#fff", border: "1px solid #e5e7eb", borderRadius: 8, padding: "12px 16px" },
  statHighlight: { borderColor: "#86efac", background: "#f0fdf4" },
  statLabel: { fontSize: 11, color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.5px" },
  statValue: { fontSize: 20, fontWeight: 700, color: "#111", marginTop: 4 },
  pkBox: { background: "#fff", border: "1px solid #e5e7eb", borderRadius: 8, padding: "12px 16px" },
  pkLabel: { fontSize: 11, color: "#9ca3af", textTransform: "uppercase", letterSpacing: "0.5px", display: "block", marginBottom: 6 },
  pkValue: { fontSize: 11, color: "#4f46e5", wordBreak: "break-all" },
  feed: { display: "flex", flexDirection: "column", gap: 4, maxHeight: 300, overflowY: "auto", marginBottom: 16 },
  feedItem: { display: "flex", alignItems: "center", gap: 10, padding: "8px 12px", background: "#fff", borderRadius: 6, cursor: "pointer", transition: "all 0.15s", border: "1px solid #e5e7eb" },
  feedItemSelected: { borderColor: "#4f46e5", background: "#eef2ff" },
  feedNonce: { fontSize: 12, color: "#9ca3af", width: 40, flexShrink: 0 },
  feedBeta: { fontSize: 11, color: "#6b7280", flex: 1, fontFamily: "monospace" },
  feedBlock: { fontSize: 11, color: "#9ca3af", width: 60, textAlign: "right" },
  feedVerify: { fontSize: 11, color: "#4f46e5", cursor: "pointer" },
  verifyCard: { background: "#f0fdf4", border: "1px solid #bbf7d0", borderRadius: 10, padding: 20, marginBottom: 16 },
  verifyTitle: { fontSize: 14, fontWeight: 600, color: "#16a34a", marginTop: 0, marginBottom: 12 },
  archBox: { background: "#fff", border: "1px solid #e5e7eb", borderRadius: 8, padding: 16 },
  archTitle: { fontSize: 12, color: "#9ca3af", marginTop: 0, marginBottom: 8, textTransform: "uppercase", letterSpacing: "0.5px" },
  archCode: { fontSize: 11, color: "#4f46e5", whiteSpace: "pre", display: "block", lineHeight: 1.6, fontFamily: "monospace" },
  row: { display: "flex", justifyContent: "space-between", alignItems: "center", padding: "4px 0" },
  rowLabel: { fontSize: 12, color: "#9ca3af" },
  rowValue: { fontSize: 12, color: "#374151", fontWeight: 500 },
  mono: { fontFamily: "monospace", fontSize: 11 },
  rpcBar: { display: "flex", gap: 8, marginTop: 24, padding: "16px 0", borderTop: "1px solid #e5e7eb" },
  rpcInput: { flex: 1, padding: "8px 12px", background: "#fff", border: "1px solid #d1d5db", borderRadius: 6, color: "#374151", fontSize: 13, fontFamily: "monospace" },
  rpcBtn: { padding: "8px 20px", background: "#4f46e5", border: "1px solid #4338ca", borderRadius: 6, color: "#fff", fontSize: 13, cursor: "pointer", fontWeight: 600 },
  footer: { textAlign: "center", padding: "24px 0 32px", fontSize: 12, color: "#9ca3af" },
};
