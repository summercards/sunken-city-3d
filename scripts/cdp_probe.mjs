// 通过 CDP 真实时间加载页面：收集 console / 异常 / 失败请求，最后截图。
// 用法: node cdp_probe.mjs <url> <waitMs> <outPng> [port]
const [url, waitMsArg, outPng, portArg] = process.argv.slice(2);
const waitMs = Number(waitMsArg || 45000);
const port = Number(portArg || 9333);

async function listTargets() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/list`);
      const list = await r.json();
      const page = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('CDP 未就绪');
}

const target = await listTargets();
const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const logs = [];
const failures = [];

function send(method, params = {}) {
  const msgId = ++id;
  ws.send(JSON.stringify({ id: msgId, method, params }));
  return new Promise((resolve, reject) => {
    pending.set(msgId, { resolve, reject });
    setTimeout(() => {
      if (pending.has(msgId)) {
        pending.delete(msgId);
        reject(new Error(`超时 ${method}`));
      }
    }, 120000);
  });
}

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    return;
  }
  if (msg.method === 'Runtime.consoleAPICalled') {
    const text = (msg.params.args || [])
      .map((a) => a.value ?? a.unserializableValue ?? a.description ?? '')
      .join(' ');
    logs.push(`[${msg.params.type}] ${text}`);
  }
  if (msg.method === 'Runtime.exceptionThrown') {
    const d = msg.params.exceptionDetails;
    logs.push(`[exception] ${d.exception?.description || d.text}`);
  }
  if (msg.method === 'Log.entryAdded') {
    logs.push(`[log:${msg.params.entry.level}] ${msg.params.entry.text}`);
  }
  if (msg.method === 'Network.loadingFailed') {
    failures.push(`${msg.params.type} ${msg.params.errorText}`);
  }
});

await new Promise((r) => ws.addEventListener('open', r, { once: true }));

await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', {
  width: 1600, height: 1000, deviceScaleFactor: 1, mobile: false,
});
await send('Page.navigate', { url });

await new Promise((r) => setTimeout(r, waitMs));

const state = await send('Runtime.evaluate', {
  expression: `JSON.stringify({
    title: document.title,
    splash: !!document.getElementById('status'),
    notice: (document.getElementById('status-notice')||{}).innerText || '',
    progress: (document.getElementById('status-progress')||{}).value ?? null,
    canvas: (() => { const c = document.querySelector('canvas'); return c ? c.width + 'x' + c.height : null; })(),
  })`,
  returnByValue: true,
});

const shot = await send('Page.captureScreenshot', { format: 'png' });
const fs = await import('node:fs/promises');
await fs.writeFile(outPng, Buffer.from(shot.data, 'base64'));

console.log('--- 页面状态 ---');
console.log(state.result.value);
console.log('--- 控制台 ---');
console.log(logs.slice(-40).join('\n') || '(无)');
console.log('--- 加载失败 ---');
console.log(failures.join('\n') || '(无)');
console.log(`截图: ${outPng}`);
ws.close();
process.exit(0);
