// 通过 CDP 打开页面、收集控制台错误、等待若干秒后截图。
// 用法: node cdp_shot.mjs <url> <out.png> [waitMs] [width] [height]
import fs from "node:fs";

const [url, out, waitMsArg, wArg, hArg] = process.argv.slice(2);
const waitMs = Number(waitMsArg || 30000);
const W = Number(wArg || 1440);
const H = Number(hArg || 900);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function wsUrl() {
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch("http://127.0.0.1:9222/json/version");
      const j = await r.json();
      if (j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl;
    } catch {}
    await sleep(250);
  }
  throw new Error("CDP not reachable");
}

const root = await wsUrl();
const ws = new WebSocket(root);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const pending = new Map();
const logs = [];
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
    return;
  }
  if (msg.method === "Runtime.consoleAPICalled") {
    const t = (msg.params.args || []).map((a) => a.value ?? a.description ?? a.type).join(" ");
    logs.push(`[${msg.params.type}] ${t}`);
  } else if (msg.method === "Runtime.exceptionThrown") {
    logs.push(`[exception] ${msg.params.exceptionDetails.text} ${msg.params.exceptionDetails.exception?.description || ""}`);
  } else if (msg.method === "Log.entryAdded") {
    logs.push(`[log:${msg.params.entry.level}] ${msg.params.entry.text}`);
  }
};

function send(method, params = {}, sessionId) {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params, sessionId }));
  return new Promise((res) => pending.set(mid, res));
}

const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
const s = (m, p) => send(m, p, sessionId);

await s("Runtime.enable");
await s("Log.enable");
await s("Page.enable");
await s("Network.enable");
await s("Network.setCacheDisabled", { cacheDisabled: true });
await s("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await s("Page.navigate", { url });

const t0 = Date.now();
let shot = null;
while (Date.now() - t0 < waitMs) {
  await sleep(2000);
  const r = await s("Page.captureScreenshot", { format: "png" });
  if (r.result?.data) {
    const buf = Buffer.from(r.result.data, "base64");
    if (!shot || buf.length !== shot.length) shot = buf;
  }
}
const probe = await s("Runtime.evaluate", {
  returnByValue: true,
  expression: `(() => {
    const notice = document.getElementById('status-notice');
    const splash = document.getElementById('status');
    const c = document.getElementById('canvas');
    return {
      notice: notice ? notice.textContent.slice(0, 500) : null,
      noticeShown: notice ? getComputedStyle(notice).display : null,
      statusLeft: splash ? !!document.getElementById('status') : false,
      canvas: c ? [c.width, c.height] : null,
      webgl2: !!document.createElement('canvas').getContext('webgl2'),
      renderer: (() => { try { const g = c.getContext('webgl2'); const d = g.getExtension('WEBGL_debug_renderer_info'); return g.getParameter(d.UNMASKED_RENDERER_WEBGL); } catch (e) { return 'n/a'; } })(),
      title: document.title,
    };
  })()`,
});

fs.writeFileSync(out, shot || Buffer.alloc(0));
console.log("PROBE", JSON.stringify(probe.result?.result?.value || probe.result, null, 1));
fs.writeFileSync("/tmp/cdp_logs.txt", logs.join("\n"));
console.log("LOGS:");
for (const l of logs.filter(l => !l.includes("Cannot set a buffer")).slice(-120)) console.log(" ", l);
ws.close();
process.exit(0);
