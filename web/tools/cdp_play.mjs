// 交互冒烟测试：打开页面 → 等加载 → 点 HUD 按钮 / 拖动 → 截图 + 测帧率。
import fs from "node:fs";

const URL_ = process.argv[2] || "http://127.0.0.1:8080/index.html";
const W = Number(process.argv[3] || 1440);
const H = Number(process.argv[4] || 900);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const ver = await (await fetch("http://127.0.0.1:9222/json/version")).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

let id = 0;
const pending = new Map();
const logs = [];
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
  if (m.method === "Runtime.consoleAPICalled") {
    logs.push(`[${m.params.type}] ` + (m.params.args || []).map((a) => a.value ?? a.description).join(" "));
  } else if (m.method === "Runtime.exceptionThrown") {
    logs.push(`[exception] ${m.params.exceptionDetails.text}`);
  }
};
const send = (method, params = {}, sessionId) => {
  const mid = ++id;
  ws.send(JSON.stringify({ id: mid, method, params, sessionId }));
  return new Promise((res) => pending.set(mid, res));
};

const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
const s = (m, p) => send(m, p, sessionId);

await s("Runtime.enable");
await s("Page.enable");
await s("Network.enable");
await s("Network.setCacheDisabled", { cacheDisabled: true });
await s("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
await s("Page.navigate", { url: URL_ });

// 等引擎起来（HUD 出现）
for (let i = 0; i < 40; i++) {
  await sleep(1500);
  const r = await s("Runtime.evaluate", { returnByValue: true, expression: "!document.getElementById('status')" });
  if (r.result?.result?.value === true) break;
}

async function shot(name) {
  const r = await s("Page.captureScreenshot", { format: "png" });
  fs.writeFileSync(name, Buffer.from(r.result.data, "base64"));
}

async function click(fx, fy, label) {
  const x = Math.round(W * fx), y = Math.round(H * fy);
  for (const type of ["mouseMoved", "mousePressed", "mouseReleased"]) {
    await s("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1, buttons: type === "mousePressed" ? 1 : 0 });
    await sleep(60);
  }
  await sleep(1200);
  console.log(`click ${label} @${x},${y}`);
}

async function drag(fx1, fy1, fx2, fy2) {
  const x1 = Math.round(W * fx1), y1 = Math.round(H * fy1);
  const x2 = Math.round(W * fx2), y2 = Math.round(H * fy2);
  await s("Input.dispatchMouseEvent", { type: "mouseMoved", x: x1, y: y1, button: "right" });
  await s("Input.dispatchMouseEvent", { type: "mousePressed", x: x1, y: y1, button: "right", buttons: 2, clickCount: 1 });
  for (let i = 1; i <= 10; i++) {
    await s("Input.dispatchMouseEvent", { type: "mouseMoved", x: x1 + ((x2 - x1) * i) / 10, y: y1 + ((y2 - y1) * i) / 10, button: "right", buttons: 2 });
    await sleep(40);
  }
  await s("Input.dispatchMouseEvent", { type: "mouseReleased", x: x2, y: y2, button: "right", clickCount: 1 });
  await sleep(1200);
}

const fps = await s("Runtime.evaluate", {
  returnByValue: true, awaitPromise: true,
  expression: `new Promise((res) => { let n = 0; const t0 = performance.now();
    function tick() { n++; if (performance.now() - t0 < 3000) requestAnimationFrame(tick); else res(+(n / ((performance.now() - t0) / 1000)).toFixed(1)); }
    requestAnimationFrame(tick); })`,
});
console.log("FPS", fps.result?.result?.value);

await shot("/tmp/play_0.png");
await click(0.49, 0.086, "背包");
await shot("/tmp/play_1.png");
await click(0.49, 0.086, "背包(关)");
await drag(0.35, 0.6, 0.55, 0.55);
await shot("/tmp/play_2.png");
console.log("LOGS:");
for (const l of logs.slice(-20)) console.log(" ", l);
ws.close();
process.exit(0);
