/**
 * sea 第二区域（横滨沉没铁道道口）+ 四周环绕遗迹群 + 水上种植 + 水底巨鲸与建筑森林
 * ---------------------------------------------------------------------------------------------------
 * 严格依据用户提供的 3 张新参考图还原，并保持原画手绘水彩风格：
 *
 * 【参考图 1 还原：第二区域「横滨沉没铁道道口」（坐标 -28, 0, -18）】
 *  - 水下清晰可见的铁道枕木、双轨钢轨与白漆道口标线
 *  - 右上角半淹没的蓝白双色复古电车车厢（带圆头灯、车门扶手与车窗）
 *  - 黑黄条纹交叉铁道警报架 + 交替闪烁的红绿信号灯
 *  - 弯头铁管持续吐出动态白蓝水流瀑布与水花圈
 *  - 两辆半淹没的黄顶青绿小汽车与蓝顶小轿车、左侧「↑ 横浜 Yokohama」蓝底白字路牌与红蓝禁停牌
 *  - 水下优雅滑翔的深蓝魔鬼鱼（Manta Ray）、船边半透明呼吸水母、小船舱内大眼黑猫伙伴与缺口睡莲叶
 *
 * 【参考图 2 还原：四周环绕的邻近区域（让画面边缘处处能感受到周边群落的存在）】
 *  - 西南邻近区（-19.5, 0, 13.5）：被水淹没的高楼方形围合天台花池（内有 3 鼎白色卫星锅、红框「ショー カミソリ」复古招牌、粉紫半淹轿车、垂挂藤蔓与可种植的热带大叶植物圃）
 *  - 东北邻近区（19.5, 0, -17.5）：断裂坍塌的藤蔓高架桥面、弯折垂入水面的三色红绿灯杆、斜插水中的紫粉「BEAUTY FASHION」广告牌、带晾衣绳与救生圈的蓝白生活船
 *
 * 【参考图 3 还原：深海建筑森林与巨鲸巡游（水底内容大升级）】
 *  - 在整片海域水底（Y = -2.5 ~ -18）铺设高耸密集的水下摩天大楼群（带密集发光/暗格窗户与天台管道设备箱）
 *  - 一头巨大的深海长须鲸（Giant Whale）摆动尾鳍在第一区域与第二区域之间的水下摩天楼峡谷间缓缓巡游，伴随水下鱼群与白色海鸟群
 *
 * 【可种植与建造动态系统 + 纯鼠标极简悬停交互】
 *  - 包含多处「水上种植园」与「遗迹修缮点」：小人走上船 → 镜头拉高锁定跟随船 → 船靠岸停留在原地 → 小人跳下船走上岸浇水播种/修缮，植物（芭蕉叶、向日葵、发光睡莲、番茄藤）与建筑模型在建造过程中实时动态生长！
 */

import { refineCharacter } from './character-art.js';
import { createEconomy, MATERIALS, HARVEST_THRESHOLD } from './economy.js';
import { createEconomyView } from './economy-view.js';
import { createNavGrid, findPath, smoothPath, isFree } from './sail-nav.js';
import { createDriftCrates } from './drift-crates.js';
import { createFishSchools } from './fish-schools.js';

import { createZoneRegistry } from './zones.js';

export function initSeaGameplay({
  THREE,
  scene,
  camera,
  renderer,
  controls,
  worldGroup,
  boatAnchorGroup,
  boatMeshGroup,
  waterPlane,
  WATER_LEVEL,
  makePainterlyMat,
  addEdgeHighlight
}) {
  // 区块注册表：海面每块水域的功能、可站立区域、上岸点、停泊位全在 zones.js 里，
  // 这里在函数最前面建立，后面摆放区块模型、取景、行走都要用。
  const zones = createZoneRegistry({ THREE, WATER_LEVEL });

  // ============================================================================
  // 1. 极简清爽 UI（顶部单颗海贝胶囊 + 鼠标真正指在模型上才浮现的轻量悬浮卡）
  // ============================================================================

  const coinPill = document.createElement('div');
  coinPill.className = 'minimal-coin-pill';
  coinPill.innerHTML = `
    <span>🐚</span>
    <span class="coin-num" id="min-coin-val">80</span>
    <span class="resource-mini" aria-label="资源数量">
      <span id="min-wood-val">🪵 0</span>
      <span id="min-parts-val">⚙ 0</span>
      <span id="min-seeds-val" title="种子">种 3</span>
      <span id="min-food-val" title="食物">食 0</span>
      <span id="min-fish-val" title="鱼">鱼 0</span>
      <span id="min-pearl-val" title="珍珠">珠 0</span>
      <span id="min-ship-val">⛵ 1</span>
    </span>
    <span class="coin-rate-subtle" id="min-coin-rate"></span>
    <span class="worker-state-dot" id="worker-status-text"></span>
  `;
  document.body.appendChild(coinPill);
  coinPill.setAttribute('aria-label', '海贝与旅人状态');
  document.getElementById('worker-status-text').setAttribute('aria-live', 'polite');

  // 右上角区域快捷导航按钮
  const controlsGroup = document.querySelector('.controls-group');
  const btnCamOriginal = document.getElementById('btn-cam-original');
  if (btnCamOriginal) {
    btnCamOriginal.innerHTML = '<span>🏡 sea</span>';
  }
  const btnCamZone2 = document.createElement('button');
  btnCamZone2.className = 'hud-btn';
  btnCamZone2.title = '派小人划船前往横滨沉没铁道道口（参考图1）';
  btnCamZone2.innerHTML = '<span>🚃 横滨铁道道口</span>';

  const btnCamZone3 = document.createElement('button');
  btnCamZone3.className = 'hud-btn';
  btnCamZone3.title = '派小人划船前往天台卫星锅种植园（参考图2）';
  btnCamZone3.innerHTML = '<span>🌱 天台种植园</span>';

  if (controlsGroup) {
    const refBtn = document.getElementById('btn-ref-toggle');
    controlsGroup.insertBefore(btnCamZone2, refBtn);
    controlsGroup.insertBefore(btnCamZone3, refBtn);
  }

  // 原画参考卡片支持切换 4 张参考图
  const refCardHeader = document.querySelector('.ref-card-header span');
  const refImg = document.querySelector('.ref-card img');
  if (refCardHeader && refImg) {
    const switchBtn = document.createElement('span');
    switchBtn.style.cssText = 'cursor:pointer;color:#ffe57f;margin-left:8px;text-decoration:underline';
    switchBtn.textContent = '[切换参考图 1/4]';
    const refList = ['./refs/reference.png', './refs/ref_yokohama.png', './refs/ref_overpass.png', './refs/ref_underwater.png'];
    let refIdx = 0;
    switchBtn.addEventListener('click', () => {
      refIdx = (refIdx + 1) % refList.length;
      refImg.src = refList[refIdx];
      switchBtn.textContent = `[切换参考图 ${refIdx + 1}/4]`;
    });
    refCardHeader.appendChild(switchBtn);
  }

  const hoverCard = document.createElement('div');
  hoverCard.className = 'hover-context-card';
  hoverCard.id = 'building-info';
  hoverCard.setAttribute('role', 'tooltip');
  hoverCard.setAttribute('aria-hidden', 'true');
  hoverCard.innerHTML = `
    <div class="hc-content">
      <div class="hc-header">
        <span class="hc-title" id="hc-title"></span>
        <span class="hc-lvl" id="hc-lvl"></span>
      </div>
      <div class="hc-summary" id="hc-summary"></div>
    </div>
  `;
  document.body.appendChild(hoverCard);

  const actionWheel = document.createElement('div');
  actionWheel.className = 'action-wheel';
  actionWheel.innerHTML = `
    <button class="action-wheel-btn boat" id="actor-boat-btn" title="划船" aria-label="划船">🚣</button>
    <button class="action-wheel-btn inspect" id="actor-inspect-btn" title="查看状态" aria-label="查看状态">◎</button>
    <button class="action-wheel-btn close" id="actor-close-btn" title="关闭">×</button>
    <span class="action-wheel-label">行动</span>
  `;
  document.body.appendChild(actionWheel);

  const destinationWheel = document.createElement('div');
  destinationWheel.className = 'destination-wheel';
  destinationWheel.innerHTML = `
    <button class="destination-btn" data-zone="zone1" title="sea" aria-label="sea">🏡</button>
    <button class="destination-btn" data-zone="zone2" title="横滨铁道" aria-label="横滨铁道">🚃</button>
    <button class="destination-btn" data-zone="zone3" title="圆弧农场" aria-label="圆弧农场">🌱</button>
    <button class="destination-btn" data-zone="zone5" title="浅水养殖" aria-label="浅水养殖">🪷</button>
    <button class="destination-btn far-sea-destination" data-zone="zone4" title="远海街町" aria-label="远海街町">🌊</button>
  `;
  document.body.appendChild(destinationWheel);

  let actorMenuOpen = false;
  let destinationMenuOpen = false;
  function positionActionMenus() {
    const anchor = explorerGroup.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 2.5, 0));
    const p = anchor.clone().project(camera);
    const visible = p.z > -1 && p.z < 1 && Math.abs(p.x) < 1 && Math.abs(p.y) < 1;
    actionWheel.style.display = destinationWheel.style.display = visible ? '' : 'none';
    if (!visible) return;
    const x = (p.x * 0.5 + 0.5) * window.innerWidth;
    const y = (-p.y * 0.5 + 0.5) * window.innerHeight;
    actionWheel.style.left = `${x}px`;
    actionWheel.style.top = `${y}px`;
    destinationWheel.style.left = `${x}px`;
    destinationWheel.style.top = `${y - 94}px`;
  }
  function closeActionMenus() {
    actorMenuOpen = false;
    destinationMenuOpen = false;
    actionWheel.classList.remove('visible');
    destinationWheel.classList.remove('visible');
  }
  function openActionMenu() {
    if (state.workerMode !== 'IDLE_ASHORE') return;
    closeActionMenus();
    actorMenuOpen = true;
    positionActionMenus();
    actionWheel.classList.add('visible');
  }
  function openDestinationMenu() {
    if (!actorMenuOpen || state.workerMode !== 'IDLE_ASHORE') return;
    destinationMenuOpen = true;
    positionActionMenus();
    destinationWheel.classList.add('visible');
  }
  document.getElementById('actor-boat-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    openDestinationMenu();
  });
  document.getElementById('actor-inspect-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    focusCameraOnWorker();
    spawnFloatTip(explorerGroup.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 1.8, 0)), state.workerMode === 'IDLE_ASHORE' ? '悠闲待机' : '正在忙碌');
  });
  document.getElementById('actor-close-btn').addEventListener('click', (e) => {
    e.stopPropagation();
    closeActionMenus();
  });
  destinationWheel.querySelectorAll('[data-zone]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const destZone = btn.dataset.zone;
      if (destZone === 'zone4' && !state.farSeaUnlocked) {
        spawnFloatTip(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 2, 0)), '⛵ 需要升级木船后才能远航');
        closeActionMenus();
        return;
      }
      if (destZone === state.currentZone) {
        closeActionMenus();
        return;
      }
      closeActionMenus();
      startSailBetweenZones(destZone, null);
    });
  });
  document.addEventListener('pointerdown', (e) => {
    if (!actionWheel.contains(e.target) && !destinationWheel.contains(e.target) && e.target !== renderer.domElement) {
      closeActionMenus();
    }
  });

  // Each building owns exactly one screen-space hotspot. Harvest always has priority.
  const resourceOrbs = new Map();
  const MATERIAL_META = {
    wood: { icon: '🪵' },
    parts: { icon: '⚙' },
    seeds: { icon: '种子' }, food: { icon: '食物' }, fish: { icon: '鱼' }, pearl: { icon: '珍珠' }
  };

  // 收集反馈：资源图标先从场景里"冒"出来，再沿一条弧线飞进右上角对应的格子里。
  const RESOURCE_ICONS = { coins: '🐚', wood: '🪵', parts: '⚙', seeds: '🌱', food: '🥕', fish: '🐟', pearl: '🫧' };
  const RESOURCE_HUD_IDS = {
    coins: 'min-coin-val', wood: 'min-wood-val', parts: 'min-parts-val',
    seeds: 'min-seeds-val', food: 'min-food-val', fish: 'min-fish-val', pearl: 'min-pearl-val'
  };

  function spawnResourceFlight(worldPos, reward) {
    const p = worldPos.clone().project(camera);
    if (p.z > 1) return;
    // 尊重减少动效偏好：不做飞行，退回到纯文字反馈。
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      spawnFloatTip(worldPos, Object.entries(reward)
        .map(([key, amount]) => `+${amount} ${MATERIAL_META[key]?.icon ?? ''}`).join(' · '));
      return;
    }
    const sx = (p.x * .5 + .5) * window.innerWidth;
    const sy = (-p.y * .5 + .5) * window.innerHeight;
    let landing = null;
    let keyIndex = 0;
    for (const [key, amount] of Object.entries(reward)) {
      if (!(amount > 0)) continue;
      const targetEl = document.getElementById(RESOURCE_HUD_IDS[key]);
      if (!targetEl) continue;
      const rect = targetEl.getBoundingClientRect();
      const tx = rect.left + rect.width / 2;
      const ty = rect.top + rect.height / 2;
      // 一次最多飞 5 个，10 份资源也不会把屏幕铺满。
      const count = Math.min(5, Math.max(1, Math.round(amount)));
      for (let i = 0; i < count; i += 1) {
        const icon = document.createElement('div');
        icon.className = 'resource-flight';
        icon.textContent = RESOURCE_ICONS[key];
        icon.setAttribute('aria-hidden', 'true');
        icon.style.left = `${sx}px`;
        icon.style.top = `${sy}px`;
        document.body.appendChild(icon);
        const angle = (Math.PI * 2 * i) / count + keyIndex * .9;
        const burst = 24 + (i % 3) * 9;
        const bx = Math.cos(angle) * burst;
        const by = Math.sin(angle) * burst - 16;
        const delay = keyIndex * 70 + i * 80;
        const anim = icon.animate([
          { transform: 'translate(-50%, -50%) scale(.25)', opacity: 0 },
          { transform: 'translate(-50%, -50%) scale(1.15)', opacity: 1, offset: .2 },
          { transform: `translate(-50%, -50%) translate(${bx}px, ${by}px) scale(1)`, opacity: 1, offset: .44 },
          { transform: `translate(-50%, -50%) translate(${tx - sx}px, ${ty - sy}px) scale(.5)`, opacity: .85 }
        ], { duration: 780, delay, easing: 'cubic-bezier(.42,.05,.35,1)', fill: 'both' });
        anim.onfinish = () => icon.remove();
        landing = Math.max(landing ?? 0, delay + 780);
      }
      keyIndex += 1;
    }
    if (landing === null) return;
    setTimeout(() => {
      for (const key of Object.keys(reward)) {
        const el = document.getElementById(RESOURCE_HUD_IDS[key]);
        if (!el) continue;
        el.classList.remove('res-bump');
        requestAnimationFrame(() => el.classList.add('res-bump'));
      }
    }, landing);
  }

  function getStageMaterials(stage) {
    return (stage && stage.materials) || {};
  }

  function getMissingCost(stage) {
    return economy.missing({ coins: stage.cost || 0, ...getStageMaterials(stage) });
  }

  function formatStageCost(stage) {
    const parts = [`${stage.cost} 🐚`];
    for (const [key, need] of Object.entries(getStageMaterials(stage))) {
      parts.push(`${need} ${MATERIAL_META[key].icon}`);
    }
    return parts.join(' · ');
  }

  function formatMissingCost(missing) {
    return Object.entries(missing)
      .map(([key, need]) => `${need} ${key === 'coins' ? '🐚' : MATERIAL_META[key].icon}`)
      .join(' · ');
  }

  function getSiteAction(site) {
    // 挂机产出要攒满 10 份才亮"可收取"，否则热点一直闪，玩家会以为漏点了什么。
    const hasResource = Math.floor(site.storedCoins) >= HARVEST_THRESHOLD;
    const maxed = site.level >= site.maxLevel;
    const stage = maxed ? null : site.stages[site.level];
    const idle = state.workerMode === 'IDLE_ASHORE' || state.workerMode === 'BOAT_IDLE' || state.workerMode === 'ROWING';
    const missing = maxed ? {} : getMissingCost(stage);
    const affordable = Object.keys(missing).length === 0;
    const requires = stage?.requires || {};
    const locked = Object.entries(requires).some(([id, level]) =>
      id === 'boat2' ? state.shipLevel < 2 : (buildSites.find(s => s.id === id)?.level || 0) < level);
    const available = !maxed && idle && !state.activeJobSite && !economy.job && affordable && !locked;
    return { mode: hasResource ? 'harvest' : 'upgrade', available, missing, maxed, stage, locked };
  }

  function harvestSite(site) {
    const orb = ensureResourceOrb(site);
    if (orb.classList.contains('collecting') || performance.now() < (orb.nextActionAt || 0)) return false;
    const gain = Math.floor(site.storedCoins);
    if (gain <= 0) return false;
    if (!economy.receive({ coins: gain })) return false;
    site.storedCoins -= gain;
    orb.nextActionAt = performance.now() + 700;
    orb.classList.add('collecting');
    spawnResourceFlight(site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0)), { coins: gain });
    animateCoinGain();
    syncCoinUI();
    setTimeout(() => {
      orb.classList.remove('collecting');
      updateResourceOrbs();
      if (hoveredTarget?.site === site) renderHoverCardContent();
    }, 280);
    return true;
  }

  function activateSite(site) {
    const action = getSiteAction(site);
    if (action.mode === 'harvest') return harvestSite(site);
    if (action.available) return queueSiteAction(site);
    if (action.locked) {
      spawnFloatTip(site.hoverAnchor.clone(), '先升级船只，再带回珍珠修建浅水池');
    }
    // 不可用时不只抖一下：直接把缺什么写在场景上方，玩家不用猜。
    const stored = Math.floor(site.storedCoins);
    if (stored > 0 && stored < HARVEST_THRESHOLD) {
      spawnFloatTip(site.hoverAnchor.clone().add(new THREE.Vector3(0, .8, 0)), `海贝积累中 ${stored}/${HARVEST_THRESHOLD}`);
    } else if (!action.maxed && state.workerMode === 'IDLE_ASHORE' && Object.keys(action.missing).length) {
      spawnFloatTip(site.hoverAnchor.clone().add(new THREE.Vector3(0, .8, 0)), `还差 ${formatMissingCost(action.missing)}`);
    }
    ensureResourceOrb(site).querySelector('.site-action-disc').animate([
      { transform: 'translateX(0)' }, { transform: 'translateX(-2px)' },
      { transform: 'translateX(2px)' }, { transform: 'translateX(0)' }
    ], { duration: 220 });
    return false;
  }

  function ensureResourceOrb(site) {
    if (resourceOrbs.has(site.id)) return resourceOrbs.get(site.id);
    const orb = document.createElement('button');
    orb.className = 'resource-orb';
    orb.type = 'button';
    orb.dataset.siteId = site.id;
    orb.setAttribute('aria-describedby', hoverCard.id);
    orb.innerHTML = '<span class="site-action-disc"><span class="site-action-icon" aria-hidden="true"></span></span>';
    orb.addEventListener('pointerdown', (e) => e.stopPropagation());
    orb.addEventListener('pointerenter', () => showHoverTarget({ type: 'site', site }));
    orb.addEventListener('pointerleave', () => scheduleHideCard());
    orb.addEventListener('focus', () => showHoverTarget({ type: 'site', site }));
    orb.addEventListener('blur', () => scheduleHideCard());
    orb.addEventListener('click', (e) => { e.stopPropagation(); activateSite(site); });
    document.body.appendChild(orb);
    resourceOrbs.set(site.id, orb);
    return orb;
  }

  function animateCoinGain() {
    elCoinVal?.classList.remove('coin-bump');
    requestAnimationFrame(() => elCoinVal?.classList.add('coin-bump'));
  }

  function updateResourceOrbs() {
    buildSites.forEach((site) => {
      const orb = ensureResourceOrb(site);
      const p = site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0)).project(camera);
      const visible = p.z > -1 && p.z < 1 && Math.abs(p.x) < .98 && Math.abs(p.y) < .98;
      orb.classList.toggle('in-view', visible);
      orb.setAttribute('tabindex', visible ? '0' : '-1');
      orb.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
      orb.style.top = `${(-p.y * .5 + .5) * window.innerHeight}px`;
      const { mode, available, missing, maxed } = getSiteAction(site);
      if (!orb.classList.contains('collecting') && orb.dataset.mode !== mode) {
        const icon = orb.querySelector('.site-action-icon');
        const previousMode = orb.dataset.mode;
        orb.dataset.mode = mode;
        icon.textContent = mode === 'harvest' ? '🐚' : '↑';
        if (previousMode) icon.animate([
          { opacity: 0, transform: 'scale(.35) translateY(5px)' },
          { opacity: 1, transform: 'scale(1.18) translateY(-1px)', offset: .7 },
          { opacity: 1, transform: 'scale(1) translateY(0)' }
        ], { duration: 360, easing: 'cubic-bezier(.2,.8,.2,1)' });
      }
      orb.classList.toggle('available', available);
      orb.classList.toggle('is-hot', hoveredTarget?.site === site && hoverCard.classList.contains('visible'));
      orb.setAttribute('aria-disabled', String(mode === 'upgrade' && !available));
      orb.setAttribute('aria-label', `${site.name}：${mode === 'harvest'
        ? `收取 ${Math.floor(site.storedCoins)} 枚海贝`
        : maxed
        ? '已满级'
        : available
        ? `升级，需要 ${formatStageCost(site.stages[site.level])}`
        : `暂不可升级，还差 ${formatMissingCost(missing)}`}`);
    });
  }

  const buildProgressEl = document.createElement('div');
  buildProgressEl.className = 'build-progress-pill';
  buildProgressEl.innerHTML = `
    <div class="bp-bar"><div class="bp-fill" id="bp-fill"></div></div>
  `;
  document.body.appendChild(buildProgressEl);

  const floatTips = new Map();
  function spawnFloatTip(worldPos, text) {
    const p = worldPos.clone().project(camera);
    if (p.z > 1) return;
    const x = (p.x * 0.5 + 0.5) * window.innerWidth;
    const y = (-p.y * 0.5 + 0.5) * window.innerHeight;
    const el = document.createElement('div');
    el.className = 'float-tip';
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
    el.textContent = text;
    document.body.appendChild(el);
    floatTips.set(el, worldPos.clone());
    setTimeout(() => { floatTips.delete(el); el.remove(); }, 1400);
  }

  // ============================================================================
  // 2. 手绘纹理生成（「↑ 横浜 Yokohama」路牌、「ショー カミソリ」红框招牌、「BEAUTY」招牌、水下大楼窗格）
  // ============================================================================
  function createYokohamaSignTexture() {
    const c = document.createElement('canvas');
    c.width = 256;
    c.height = 384;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#1d76c2';
    ctx.fillRect(0, 0, 256, 384);
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 14;
    ctx.strokeRect(10, 10, 236, 364);
    // 白色向上箭头
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.moveTo(128, 45);
    ctx.lineTo(172, 105);
    ctx.lineTo(142, 105);
    ctx.lineTo(142, 165);
    ctx.lineTo(114, 165);
    ctx.lineTo(114, 105);
    ctx.lineTo(84, 105);
    ctx.closePath();
    ctx.fill();

    ctx.font = 'bold 58px "PingFang SC", "Hiragino Sans GB", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('横浜', 128, 248);
    ctx.font = 'bold 34px sans-serif';
    ctx.fillText('Yokohama', 128, 305);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  function createKamisoriSignTexture() {
    const c = document.createElement('canvas');
    c.width = 256;
    c.height = 256;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#d8dfd0';
    ctx.fillRect(0, 0, 256, 256);
    ctx.strokeStyle = '#b84238';
    ctx.lineWidth = 18;
    ctx.strokeRect(9, 9, 238, 238);
    ctx.fillStyle = '#c84b38';
    ctx.font = 'bold 56px "PingFang SC", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('ショー', 128, 108);
    ctx.font = 'bold 44px "PingFang SC", sans-serif';
    ctx.fillText('カミソリ', 128, 176);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  function createBeautySignTexture() {
    const c = document.createElement('canvas');
    c.width = 256;
    c.height = 256;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#9c8eb8';
    ctx.fillRect(0, 0, 256, 256);
    ctx.strokeStyle = '#dcd4eb';
    ctx.lineWidth = 12;
    ctx.strokeRect(10, 10, 236, 236);
    ctx.fillStyle = '#f5effc';
    ctx.font = 'bold 46px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('BEAUTY', 128, 128);
    ctx.font = 'bold 28px sans-serif';
    ctx.fillText('FASHION', 128, 180);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  // 动态收集所有随风/随水摇曳的植物、水母、水流粒子等
  const dynamicAnimItems = [];

  // 通用手绘大叶热带植物/花朵生成器（用于可种植花圃和场景装饰）
  function createTropicalPlantCluster(scale = 1, hasFlowers = false, flowerColor = '#ffcf48') {
    const group = new THREE.Group();
    group.scale.setScalar(scale);
    const leafMat1 = makePainterlyMat('#42d668');
    const leafMat2 = makePainterlyMat('#6ef064');
    const stemMat = makePainterlyMat('#268c46');

    const leafCount = 6;
    for (let i = 0; i < leafCount; i++) {
      const ang = (i / leafCount) * Math.PI * 2 + (Math.random() - 0.5) * 0.3;
      const stem = new THREE.Group();
      stem.rotation.y = ang;

      const petiole = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.06, 0.75, 6), stemMat);
      petiole.position.set(0, 0.35, 0.22);
      petiole.rotation.x = 0.45;
      stem.add(petiole);

      // 宽阔手绘芭蕉叶/龟背竹叶面
      const blade = new THREE.Mesh(
        new THREE.SphereGeometry(0.42, 8, 8),
        i % 2 === 0 ? leafMat1 : leafMat2
      );
      blade.scale.set(0.85, 0.16, 1.55);
      blade.position.set(0, 0.68, 0.65);
      blade.rotation.x = 0.35;
      addEdgeHighlight(blade, '#b8ff88', 0.45);
      stem.add(blade);

      group.add(stem);
      dynamicAnimItems.push({
        type: 'sway_leaf',
        obj: stem,
        baseX: 0,
        speed: 2.0 + Math.random(),
        phase: i * 1.1
      });
    }

    if (hasFlowers) {
      for (let f = 0; f < 3; f++) {
        const fang = (f * Math.PI * 2) / 3 + 0.4;
        const flower = new THREE.Mesh(
          new THREE.DodecahedronGeometry(0.24, 0),
          makePainterlyMat(flowerColor)
        );
        flower.position.set(Math.cos(fang) * 0.35, 0.95 + (f % 2) * 0.18, Math.sin(fang) * 0.35);
        addEdgeHighlight(flower, '#fff9b8', 0.65);
        group.add(flower);
      }
    }
    return group;
  }

  // 缺口睡莲浮叶生成器（还原图1与图2水面上星罗棋布的圆缺口绿睡莲）
  function createLilyPadPatch(cx, cz, count = 6, spread = 2.8) {
    const pGroup = new THREE.Group();
    pGroup.position.set(cx, WATER_LEVEL + 0.03, cz);
    const padMat1 = makePainterlyMat('#3ec966');
    const padMat2 = makePainterlyMat('#5ee06e');
    for (let i = 0; i < count; i++) {
      const r = 0.32 + Math.random() * 0.38;
      // 留出 0.35 弧度缺口模拟睡莲分叉叶
      const geo = new THREE.CylinderGeometry(r, r, 0.04, 14, 1, false, 0.35, Math.PI * 2 - 0.35);
      const pad = new THREE.Mesh(geo, i % 2 === 0 ? padMat1 : padMat2);
      const ang = (i / count) * Math.PI * 2 + Math.random() * 0.5;
      const dist = (0.25 + Math.random() * 0.75) * spread;
      pad.position.set(Math.cos(ang) * dist, (i % 3) * 0.005, Math.sin(ang) * dist);
      pad.rotation.y = Math.random() * Math.PI * 2;
      addEdgeHighlight(pad, '#9eff9e', 0.45);
      pGroup.add(pad);
    }
    worldGroup.add(pGroup);
    return pGroup;
  }

  // ============================================================================
  // 3. 在小船上添加参考图 1 的大眼黑猫伙伴 + 船边发光半透明水母
  // ============================================================================
  const blackCatGroup = new THREE.Group();
  blackCatGroup.position.set(0.32, 0.56, 0.88); // 坐在船头第1排座位上陪伴小人
  blackCatGroup.rotation.y = -0.25;
  boatMeshGroup.add(blackCatGroup);

  const catMat = makePainterlyMat('#242834');
  const catBody = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 10), catMat);
  catBody.scale.set(0.95, 1.15, 0.9);
  catBody.position.y = 0.18;
  blackCatGroup.add(catBody);

  const catHead = new THREE.Mesh(new THREE.SphereGeometry(0.19, 12, 12), catMat);
  catHead.scale.set(1.1, 0.95, 0.95);
  catHead.position.set(0, 0.42, 0.04);
  blackCatGroup.add(catHead);

  // 尖尖猫耳
  [-0.11, 0.11].forEach((ex) => {
    const ear = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.16, 4), catMat);
    ear.position.set(ex, 0.58, 0.04);
    ear.rotation.z = ex < 0 ? 0.22 : -0.22;
    blackCatGroup.add(ear);
  });

  // 标志性的圆溜溜大白眼珠 + 黑瞳孔
  const eyeWhiteMat = new THREE.MeshBasicMaterial({ color: '#ffffff' });
  const pupilMat = new THREE.MeshBasicMaterial({ color: '#11131a' });
  [-0.075, 0.075].forEach((ex) => {
    const eyeW = new THREE.Mesh(new THREE.SphereGeometry(0.058, 10, 10), eyeWhiteMat);
    eyeW.scale.set(1, 1.15, 0.5);
    eyeW.position.set(ex, 0.43, 0.19);
    blackCatGroup.add(eyeW);

    const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.026, 8, 8), pupilMat);
    pupil.position.set(ex, 0.43, 0.225);
    blackCatGroup.add(pupil);
  });

  // 船头左舷旁漂浮的半透明发光小水母（还原图1小船左下侧带白描边的透明水母）
  function createGlowingJellyfish(parent, x, y, z, scale = 1) {
    const jGroup = new THREE.Group();
    jGroup.position.set(x, y, z);
    jGroup.scale.setScalar(scale);

    const domeGeo = new THREE.SphereGeometry(0.34, 14, 10, 0, Math.PI * 2, 0, Math.PI * 0.58);
    const domeMat = new THREE.MeshBasicMaterial({
      color: '#a8f8ff',
      transparent: true,
      opacity: 0.52,
      side: THREE.DoubleSide
    });
    const dome = new THREE.Mesh(domeGeo, domeMat);
    addEdgeHighlight(dome, '#ffffff', 0.85);
    jGroup.add(dome);

    // 触手
    for (let t = 0; t < 4; t++) {
      const ang = (t * Math.PI) / 2 + 0.3;
      const tentacle = new THREE.Mesh(
        new THREE.CylinderGeometry(0.018, 0.012, 0.58, 6),
        new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.78 })
      );
      tentacle.position.set(Math.cos(ang) * 0.12, -0.26, Math.sin(ang) * 0.12);
      jGroup.add(tentacle);
    }

    parent.add(jGroup);
    dynamicAnimItems.push({ type: 'jellyfish', obj: jGroup, baseY: y, phase: x + z });
    return jGroup;
  }
  createGlowingJellyfish(boatAnchorGroup, -1.55, 0.15, 0.85, 0.95);

  // ============================================================================
  // 4. 构建第二区域：【横滨沉没铁道道口（Yokohama Submerged Railway Crossing）】
  //    中心位于 (-28.0, 0, -18.0)，从第一区域向西北望去刚好在迷雾边缘隐约可见，划船数秒即达
  // ============================================================================
  const zone2Root = new THREE.Group();
  zone2Root.position.copy(zones.get('zone2').origin);
  worldGroup.add(zone2Root);

  // 4.1 水下铁道海床基座 + 枕木 + 双轨钢轨 + 白色道口停止线（严格对齐参考图1中央）
  const trackBedGroup = new THREE.Group();
  trackBedGroup.position.set(0, WATER_LEVEL - 0.55, 0);
  trackBedGroup.rotation.y = -0.35;
  zone2Root.add(trackBedGroup);

  const roadBedMesh = new THREE.Mesh(
    new THREE.BoxGeometry(17.0, 14.0, 14.0),
    makePainterlyMat('#1b88b8', {}, true)
  );
  roadBedMesh.position.y = -7.05;
  trackBedGroup.add(roadBedMesh);

  // 铁道碎石路基与枕木
  const sleeperMat = makePainterlyMat('#26769e', {}, true);
  for (let i = -7; i <= 7; i++) {
    const sleeper = new THREE.Mesh(new THREE.BoxGeometry(0.48, 0.14, 3.6), sleeperMat);
    sleeper.position.set(i * 1.05, 0.08, -0.4);
    trackBedGroup.add(sleeper);
  }

  // 两条平行钢轨（带出水高光段）
  const railMat = makePainterlyMat('#78d8e8');
  [-1.1, 1.1].forEach((rz) => {
    const rail = new THREE.Mesh(new THREE.BoxGeometry(16.5, 0.22, 0.22), railMat);
    rail.position.set(0, 0.22, rz - 0.4);
    addEdgeHighlight(rail, '#e8ffff', 0.65);
    trackBedGroup.add(rail);
  });

  // 道口两侧的白色斑马护栏线
  const whiteLineMat = new THREE.MeshBasicMaterial({ color: '#ecfeff' });
  [-1.95, 1.15].forEach((lz) => {
    const lineBar = new THREE.Mesh(new THREE.BoxGeometry(7.2, 0.26, 0.26), whiteLineMat);
    lineBar.position.set(-2.6, 0.26, lz);
    trackBedGroup.add(lineBar);
  });

  // 4.1b 道口向远处延伸的第二段轨道：把第二区域从“单个模型”拉成一条可读的淹没街道
  const trackExtensionGroup = new THREE.Group();
  trackExtensionGroup.position.set(0, WATER_LEVEL - 0.52, -5.2);
  trackExtensionGroup.rotation.y = -0.35;
  zone2Root.add(trackExtensionGroup);
  for (let i = -4; i <= 4; i++) {
    const sleeper = new THREE.Mesh(
      new THREE.BoxGeometry(0.42, 0.12, 3.25),
      sleeperMat
    );
    sleeper.position.set(i * 1.08, 0.08, 0);
    trackExtensionGroup.add(sleeper);
  }
  [-1.1, 1.1].forEach((rz) => {
    const rail = new THREE.Mesh(new THREE.BoxGeometry(10.5, 0.2, 0.2), railMat);
    rail.position.set(0, 0.22, rz);
    addEdgeHighlight(rail, '#d8ffff', 0.55);
    trackExtensionGroup.add(rail);
  });

  // 道口前景的低矮排水渠与褪色黄白停止线，作为船湾到站台的视觉引导
  const crossingDrain = new THREE.Mesh(
    new THREE.BoxGeometry(7.8, 0.18, 0.58),
    makePainterlyMat('#155e88', {}, true)
  );
  crossingDrain.position.set(0.4, WATER_LEVEL + 0.08, 2.75);
  crossingDrain.rotation.y = -0.35;
  zone2Root.add(crossingDrain);
  [-2.05, 1.1].forEach((lz) => {
    const stopLine = new THREE.Mesh(
      new THREE.BoxGeometry(5.4, 0.12, 0.18),
      makePainterlyMat('#e8d88e')
    );
    stopLine.position.set(-1.8, WATER_LEVEL + 0.16, lz);
    stopLine.rotation.y = -0.35;
    zone2Root.add(stopLine);
  });

  // 4.2 左上角高架电车混凝土站台（带立柱支撑 + 站台顶面可种植花床！）
  const stationPlatformGroup = new THREE.Group();
  stationPlatformGroup.position.set(-4.8, WATER_LEVEL + 1.35, -3.5);
  stationPlatformGroup.rotation.y = -0.35;
  zone2Root.add(stationPlatformGroup);

  const platSlab = new THREE.Mesh(
    new THREE.BoxGeometry(8.2, 0.62, 4.6),
    makePainterlyMat('#d8e6d8')
  );
  platSlab.castShadow = true;
  platSlab.receiveShadow = true;
  addEdgeHighlight(platSlab, '#f5fff5', 0.6);
  stationPlatformGroup.add(platSlab);

  // 站台边缘绿色青苔包角与水下圆柱桥墩
  [-2.6, 2.2].forEach((px) => {
    const pillar = new THREE.Mesh(
      new THREE.CylinderGeometry(0.45, 0.48, 8.0, 12),
      makePainterlyMat('#4d7c82', {}, true)
    );
    pillar.position.set(px, -4.1, 1.2);
    stationPlatformGroup.add(pillar);
  });

  // 站台遮雨棚柱与信号盒
  const roofPillar = new THREE.Mesh(
    new THREE.BoxGeometry(0.46, 2.8, 0.46),
    makePainterlyMat('#4a665a')
  );
  roofPillar.position.set(1.2, 1.6, -0.4);
  stationPlatformGroup.add(roofPillar);

  const stationCanopy = new THREE.Mesh(
    new THREE.BoxGeometry(6.8, 0.35, 3.6),
    makePainterlyMat('#5b8472')
  );
  stationCanopy.position.set(0.2, 3.05, -0.4);
  stationCanopy.rotation.z = -0.08;
  addEdgeHighlight(stationCanopy, '#b8f0d4', 0.5);
  stationPlatformGroup.add(stationCanopy);

  // 4.3 右上角半淹没蓝白复古电车车厢：车身主轴与铁轨统一沿 X 方向
  //     这样车厢、枕木、站台边线和道口停止线会读成同一条街区轴线。
  const trainCarGroup = new THREE.Group();
  trainCarGroup.position.set(4.5, WATER_LEVEL + 1.25, -3.2);
  trainCarGroup.rotation.y = -0.35;
  trainCarGroup.rotation.z = 0.035;
  zone2Root.add(trainCarGroup);

  const trainLower = new THREE.Mesh(
    new THREE.BoxGeometry(8.2, 1.55, 3.8),
    makePainterlyMat('#2b6cb8')
  );
  trainLower.position.y = -0.45;
  addEdgeHighlight(trainLower, '#8cd4ff', 0.55);
  trainCarGroup.add(trainLower);

  const trainUpper = new THREE.Mesh(
    new THREE.BoxGeometry(8.05, 1.75, 3.72),
    makePainterlyMat('#e8ebd5')
  );
  trainUpper.position.y = 1.15;
  trainUpper.castShadow = true;
  addEdgeHighlight(trainUpper, '#ffffff', 0.65);
  trainCarGroup.add(trainUpper);

  const trainRoof = new THREE.Mesh(
    new THREE.BoxGeometry(7.8, 0.38, 3.5),
    makePainterlyMat('#547478')
  );
  trainRoof.position.y = 2.18;
  trainCarGroup.add(trainRoof);

  // 电车车头朝向道口中心：大挡风窗与两盏圆头灯落在 X 正向端
  const trainFrontWin = new THREE.Mesh(
    new THREE.BoxGeometry(0.16, 1.15, 2.6),
    makePainterlyMat('#263850')
  );
  trainFrontWin.position.set(4.02, 1.22, 0);
  trainCarGroup.add(trainFrontWin);

  const headlightMat = new THREE.MeshBasicMaterial({ color: '#ffe875' });
  [-1.05, 1.05].forEach((hz) => {
    const lamp = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 0.16, 12), headlightMat);
    lamp.rotation.z = Math.PI / 2;
    lamp.position.set(4.1, 0.05, hz);
    trainCarGroup.add(lamp);
  });

  // 4.4 黑黄条纹铁道道口警报灯杆（带红绿闪烁信号灯）
  const crossingSignalGroup = new THREE.Group();
  crossingSignalGroup.position.set(5.4, WATER_LEVEL, 1.4);
  zone2Root.add(crossingSignalGroup);

  for (let s = 0; s < 7; s++) {
    const seg = new THREE.Mesh(
      new THREE.CylinderGeometry(0.16, 0.16, 0.55, 10),
      makePainterlyMat(s % 2 === 0 ? '#f5c838' : '#262b34')
    );
    seg.position.y = 0.25 + s * 0.55;
    crossingSignalGroup.add(seg);
  }
  // 交叉 X 形黑黄警告牌
  [-0.65, 0.65].forEach((rz) => {
    const crossBoard = new THREE.Mesh(
      new THREE.BoxGeometry(2.1, 0.32, 0.12),
      makePainterlyMat('#f5c838')
    );
    crossBoard.position.set(0, 3.25, 0.18);
    crossBoard.rotation.z = rz;
    addEdgeHighlight(crossBoard, '#262b34', 0.8);
    crossingSignalGroup.add(crossBoard);
  });
  const signalLightBulb = new THREE.Mesh(
    new THREE.SphereGeometry(0.26, 10, 10),
    new THREE.MeshBasicMaterial({ color: '#38e878' })
  );
  signalLightBulb.position.set(-0.38, 2.25, 0.25);
  crossingSignalGroup.add(signalLightBulb);
  dynamicAnimItems.push({ type: 'signal_blink', obj: signalLightBulb });

  // 4.5 弯头排水铁管与动态倾泻瀑布（严格还原图1中间偏左的弯管吐水与白色水花圈）
  const pipeWaterfallGroup = new THREE.Group();
  pipeWaterfallGroup.position.set(-2.2, WATER_LEVEL, 1.65);
  zone2Root.add(pipeWaterfallGroup);

  const pipeMat = makePainterlyMat('#4e706a');
  const pipeVert = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 1.8, 12), pipeMat);
  pipeVert.position.set(-0.6, 0.65, 0);
  pipeWaterfallGroup.add(pipeVert);

  const pipeElbow = new THREE.Mesh(new THREE.SphereGeometry(0.45, 12, 12), pipeMat);
  pipeElbow.position.set(-0.6, 1.55, 0);
  pipeWaterfallGroup.add(pipeElbow);

  const pipeSpout = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.95, 12), pipeMat);
  pipeSpout.rotation.z = Math.PI / 2 + 0.35;
  pipeSpout.position.set(-0.18, 1.42, 0);
  pipeWaterfallGroup.add(pipeSpout);

  // 倾泻而下的蓝白水柱与水面溅射白沫圈
  const waterStreamMesh = new THREE.Mesh(
    new THREE.CylinderGeometry(0.28, 0.44, 1.35, 10),
    new THREE.MeshBasicMaterial({ color: '#64f2ff', transparent: true, opacity: 0.86 })
  );
  waterStreamMesh.position.set(0.22, 0.65, 0);
  pipeWaterfallGroup.add(waterStreamMesh);

  const splashRing = new THREE.Mesh(
    new THREE.RingGeometry(0.32, 0.72, 18),
    new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.9, side: THREE.DoubleSide })
  );
  splashRing.rotation.x = -Math.PI / 2;
  splashRing.position.set(0.22, 0.05, 0);
  pipeWaterfallGroup.add(splashRing);
  dynamicAnimItems.push({ type: 'waterfall', stream: waterStreamMesh, splash: splashRing });

  // 4.6 两辆半淹没的复古小汽车（黄顶青绿车身 + 蓝顶深青车身，还原图1右侧）
  function createSubmergedCar(x, y, z, rotY, bodyCol, roofCol) {
    const car = new THREE.Group();
    car.position.set(x, y, z);
    car.rotation.y = rotY;
    car.rotation.x = 0.08;

    const lower = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.85, 3.6), makePainterlyMat(bodyCol));
    lower.position.y = -0.15;
    addEdgeHighlight(lower, '#aef8ff', 0.45);
    car.add(lower);

    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.82, 0.78, 2.05), makePainterlyMat(roofCol));
    cabin.position.set(0, 0.62, -0.15);
    addEdgeHighlight(cabin, '#fff8c8', 0.55);
    car.add(cabin);

    const windshield = new THREE.Mesh(new THREE.BoxGeometry(1.62, 0.58, 0.12), makePainterlyMat('#1d4e6e'));
    windshield.position.set(0, 0.6, 0.88);
    windshield.rotation.x = -0.25;
    car.add(windshield);

    car.userData.buoyant = true;
    zone2Root.add(car);
    return car;
  }
  createSubmergedCar(2.3, WATER_LEVEL + 0.05, 1.4, -0.58, '#28969e', '#e8d858');
  createSubmergedCar(3.8, WATER_LEVEL - 0.15, 3.6, -0.45, '#1e6e9e', '#68b4d8');

  // 4.7 左侧「↑ 横浜 Yokohama」路牌与红蓝禁止停车圆牌
  const yokoSignMesh = new THREE.Mesh(
    new THREE.BoxGeometry(1.5, 2.3, 0.14),
    new THREE.MeshBasicMaterial({ map: createYokohamaSignTexture() })
  );
  yokoSignMesh.position.set(-5.8, WATER_LEVEL + 0.95, 2.3);
  yokoSignMesh.rotation.set(0.12, 0.48, -0.18);
  addEdgeHighlight(yokoSignMesh, '#ffffff', 0.75);
  zone2Root.add(yokoSignMesh);

  // 4.8 水下优雅游动的深蓝魔鬼鱼（Manta Ray，还原图1小船下方大片的深蓝魔鬼鱼剪影与气泡）
  const mantaGroup = new THREE.Group();
  mantaGroup.position.set(-0.5, WATER_LEVEL - 1.15, 4.2);
  zone2Root.add(mantaGroup);

  const mantaMat = makePainterlyMat('#0d4f9c', {}, true);
  const mantaDisk = new THREE.Mesh(new THREE.ConeGeometry(1.85, 0.32, 4), mantaMat);
  mantaDisk.scale.set(1.35, 0.35, 1.0);
  mantaDisk.rotation.y = Math.PI / 4;
  addEdgeHighlight(mantaDisk, '#4ce8ff', 0.45);
  mantaGroup.add(mantaDisk);

  const mantaTail = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.01, 2.2, 6), mantaMat);
  mantaTail.rotation.x = Math.PI / 2;
  mantaTail.position.z = -1.9;
  mantaGroup.add(mantaTail);
  dynamicAnimItems.push({
    type: 'manta_glide',
    obj: mantaGroup,
    center: new THREE.Vector3(-0.5, WATER_LEVEL - 1.15, 3.8),
    rx: 3.2,
    rz: 2.4
  });

  // 连接船湾、靠岸边缘与站台的短栈桥：让“船停在这里 → 人走上岸”有明确的空间叙事
  const dockWalkwayGroup = new THREE.Group();
  dockWalkwayGroup.position.set(0, WATER_LEVEL + 0.78, 0);
  zone2Root.add(dockWalkwayGroup);
  const dockPlankMat = makePainterlyMat('#b87950');
  [
    [2.05, 2.55, -0.28],
    [1.15, 1.95, -0.34],
    [0.25, 1.35, -0.38],
    [-0.65, 0.78, -0.44],
    [-1.55, 0.18, -0.52]
  ].forEach(([px, pz, rot]) => {
    const plank = new THREE.Mesh(new THREE.BoxGeometry(1.35, 0.18, 0.62), dockPlankMat);
    plank.position.set(px, 0, pz);
    plank.rotation.y = rot;
    addEdgeHighlight(plank, '#f5c58e', 0.38);
    dockWalkwayGroup.add(plank);
  });
  [-1.7, -0.35, 1.0].forEach((px, idx) => {
    const post = new THREE.Mesh(
      new THREE.CylinderGeometry(0.12, 0.16, 1.65, 8),
      makePainterlyMat('#6f503d')
    );
    post.position.set(px, -0.45, 0.45 + idx * 0.25);
    dockWalkwayGroup.add(post);
  });

  // 在铁道道口水面散布睡莲叶
  createLilyPadPatch(-28.5, -22.5, 7, 2.5);
  createLilyPadPatch(-24.2, -12.5, 8, 2.8);

  // ============================================================================
  // 5. 构建四周环绕的邻近区域（参考图 2：让视野边缘处处感受到周边区域在边上！）
  // ============================================================================
  // 5.1 西南邻近区：【天台卫星锅种植园】（坐标 -19.5, 0, 13.5 —— 从第一区域往左下看直接能感受到它在边上）
  const zone3Root = new THREE.Group();
  zone3Root.position.set(zones.get('zone3').origin.x, 0, zones.get('zone3').origin.z);
  zone3Root.rotation.y = 0.28;
  worldGroup.add(zone3Root);

  // 淹没的复古大楼本体与顶部方形围墙种植池（严格还原图2下方方形屋顶花坛）
  const planterTowerBody = new THREE.Mesh(
    new THREE.BoxGeometry(7.6, 22.0, 7.6),
    makePainterlyMat('#8fa68a', {}, true)
  );
  planterTowerBody.position.y = WATER_LEVEL - 9.4;
  addEdgeHighlight(planterTowerBody, '#c8f0be', 0.4);
  zone3Root.add(planterTowerBody);

  // 屋顶围墙框（形成内部土壤种植槽）
  const parapetMat = makePainterlyMat('#c8d4b8');
  [
    [0, 5.0, 10.6, 0.85, 0.45],
    [0, -5.0, 10.6, 0.85, 0.45],
    [5.0, 0, 0.45, 0.85, 10.6],
    [-5.0, 0, 0.45, 0.85, 10.6]
  ].forEach(([px, pz, pw, ph, pd]) => {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(pw, ph, pd), parapetMat);
    wall.position.set(px, WATER_LEVEL + 1.85, pz);
    addEdgeHighlight(wall, '#f2ffe6', 0.5);
    zone3Root.add(wall);
  });
  // 扩大的屋顶土地：让种植区从中心花池扩展到更完整的天台范围。
  const rooftopSoilPatch = new THREE.Mesh(
    new THREE.BoxGeometry(8.85, 0.12, 8.85),
    makePainterlyMat('#6f9a4c')
  );
  rooftopSoilPatch.position.set(0, WATER_LEVEL + 1.76, -0.35);
  zone3Root.add(rooftopSoilPatch);

  const planterSoil = new THREE.Mesh(
    new THREE.BoxGeometry(9.35, 0.35, 9.35),
    makePainterlyMat('#4a7842')
  );
  planterSoil.position.y = WATER_LEVEL + 1.55;
  zone3Root.add(planterSoil);

  // 标志性的正立面红框广告牌（「ショー カミソリ」，严格还原图2下方大楼立面）
  const kamisoriSign = new THREE.Mesh(
    new THREE.BoxGeometry(3.1, 3.2, 0.18),
    new THREE.MeshBasicMaterial({ map: createKamisoriSignTexture() })
  );
  kamisoriSign.position.set(-1.1, WATER_LEVEL + 0.45, 3.88);
  addEdgeHighlight(kamisoriSign, '#ff9482', 0.65);
  zone3Root.add(kamisoriSign);

  // 屋顶花池里的 3 个白色圆盘卫星天线锅（还原图2花坛内的三个白圆碟）
  [-1.6, 0.0, 1.5].forEach((dx, idx) => {
    const dishWrap = new THREE.Group();
    dishWrap.position.set(dx, WATER_LEVEL + 2.15, 1.2 - idx * 0.35);
    dishWrap.rotation.set(-0.45, 0.35 + idx * 0.2, 0);
    const dishCone = new THREE.Mesh(
      new THREE.CylinderGeometry(0.68, 0.18, 0.26, 16),
      makePainterlyMat('#e8f2f4')
    );
    dishCone.rotation.x = Math.PI / 2;
    addEdgeHighlight(dishCone, '#ffffff', 0.7);
    dishWrap.add(dishCone);
    zone3Root.add(dishWrap);
  });

  // 初始自带的少量大叶绿植 + 旁边的半淹紫粉色汽车与断裂桥面（还原图2右下角）
  const initialPlants = createTropicalPlantCluster(1.15, false);
  initialPlants.position.set(-2.2, WATER_LEVEL + 1.7, -1.6);
  zone3Root.add(initialPlants);

  // 这两处是打捞台的环境装饰，按打捞点的相对偏移摆放，打捞台搬动时会一起走。
  const salvageSpot = zones.harborPoint('salvage') || new THREE.Vector3(-12, WATER_LEVEL, 13);
  createSubmergedCar(salvageSpot.x - 0.5, WATER_LEVEL + 0.15, salvageSpot.z + 1.5, 0.42, '#8b68e8', '#d874aa');
  createLilyPadPatch(salvageSpot.x - 3.5, salvageSpot.z - 1.8, 9, 3.2);

  // 5.2 东北邻近区：【藤蔓断桥与晾衣生活船】（坐标 19.5, 0, -17.5 —— 从第一区域往右上看直接能感受到它在边上）
  const zone4Root = new THREE.Group();
  zone4Root.position.copy(zones.get('zone4').origin);
  zone4Root.rotation.y = -0.25;
  worldGroup.add(zone4Root);

  // 米黄色欧式淹没残楼（还原图2上方背景的米黄多孔窗老楼）
  const euroBuilding = new THREE.Mesh(
    new THREE.BoxGeometry(8.4, 20.0, 6.8),
    makePainterlyMat('#c8be96', {}, true)
  );
  euroBuilding.position.set(-2.5, WATER_LEVEL - 4.2, -3.2);
  addEdgeHighlight(euroBuilding, '#f5ecc8', 0.45);
  zone4Root.add(euroBuilding);

  // 崩塌断裂的混凝土高架桥面（覆满垂挂绿藤，还原图2右上角断桥）
  for (let b = 0; b < 3; b++) {
    const slab = new THREE.Mesh(
      new THREE.BoxGeometry(3.4, 0.68, 4.6),
      makePainterlyMat('#b8c6a8')
    );
    slab.position.set(2.4 + b * 2.8, WATER_LEVEL + 3.2 - b * 0.45, -1.2 + b * 1.4);
    slab.rotation.set(0.12 * b, -0.15, -0.18 * b);
    addEdgeHighlight(slab, '#e6f5d0', 0.55);
    zone4Root.add(slab);

    // 桥面垂下的藤蔓条
    for (let v = 0; v < 4; v++) {
      const vine = new THREE.Mesh(
        new THREE.BoxGeometry(0.18, 1.8 + (v % 2) * 0.8, 0.18),
        makePainterlyMat('#389e52')
      );
      vine.position.set(1.2 + b * 2.8 + v * 0.65, WATER_LEVEL + 2.1 - b * 0.4, 0.8 + b * 1.4);
      zone4Root.add(vine);
    }
  }

  // 弯折垂向水面的路灯与三色红绿灯（还原图2正上方经典的弯曲红绿灯杆）
  const bentPoleCurve = new THREE.QuadraticBezierCurve3(
    new THREE.Vector3(-4.2, WATER_LEVEL, 0.5),
    new THREE.Vector3(-3.2, WATER_LEVEL + 5.2, 1.2),
    new THREE.Vector3(-0.8, WATER_LEVEL + 4.1, 2.2)
  );
  const bentPoleMesh = new THREE.Mesh(
    new THREE.TubeGeometry(bentPoleCurve, 16, 0.14, 8, false),
    makePainterlyMat('#687c74')
  );
  zone4Root.add(bentPoleMesh);

  const trafficLightBox = new THREE.Mesh(
    new THREE.BoxGeometry(0.52, 1.35, 0.42),
    makePainterlyMat('#36423e')
  );
  trafficLightBox.position.set(-0.8, WATER_LEVEL + 3.7, 2.2);
  trafficLightBox.rotation.z = 0.48;
  zone4Root.add(trafficLightBox);

  // 斜插在水里的「BEAUTY FASHION」紫粉色广告牌（还原图2左上角）
  const beautyBoard = new THREE.Mesh(
    new THREE.BoxGeometry(2.8, 2.8, 0.16),
    new THREE.MeshBasicMaterial({ map: createBeautySignTexture() })
  );
  beautyBoard.position.set(-7.5, WATER_LEVEL + 0.65, 2.5);
  beautyBoard.rotation.set(0.22, 0.55, 0.38);
  zone4Root.add(beautyBoard);

  // 停泊在断桥水巷里的蓝白生活小渔船（带白色驾驶室、橙色救生圈与彩色晾衣绳，还原图2中左）
  const houseBoatGroup = new THREE.Group();
  houseBoatGroup.position.set(-1.5, WATER_LEVEL + 0.08, 3.6);
  houseBoatGroup.rotation.y = 0.42;
  zone4Root.add(houseBoatGroup);

  const hbHull = new THREE.Mesh(new THREE.BoxGeometry(2.3, 0.9, 5.2), makePainterlyMat('#2682c8'));
  addEdgeHighlight(hbHull, '#ffffff', 0.65);
  houseBoatGroup.add(hbHull);

  const hbCabin = new THREE.Mesh(new THREE.BoxGeometry(1.85, 1.65, 2.1), makePainterlyMat('#f2f6eb'));
  hbCabin.position.set(0, 1.2, -0.3);
  addEdgeHighlight(hbCabin, '#ffffff', 0.7);
  houseBoatGroup.add(hbCabin);

  // 橙色救生圈
  const lifebuoy = new THREE.Mesh(
    new THREE.TorusGeometry(0.32, 0.11, 8, 16),
    makePainterlyMat('#f57c38')
  );
  lifebuoy.rotation.y = Math.PI / 2;
  lifebuoy.position.set(1.18, 0.35, -0.8);
  houseBoatGroup.add(lifebuoy);

  // 船头晾晒的彩色衣服
  ['#a8f0c8', '#f5e898', '#ff8882'].forEach((col, idx) => {
    const cloth = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.48, 0.38), makePainterlyMat(col));
    cloth.position.set(0, 1.65, 1.15 + idx * 0.55);
    houseBoatGroup.add(cloth);
  });
  dynamicAnimItems.push({ type: 'bob_boat', obj: houseBoatGroup, baseY: WATER_LEVEL + 0.08 });

  // ============================================================================
  // 6. 水底世界大升级（参考图 3：高耸密集的水下摩天楼森林 + 深海巨鲸巡游）
  // ============================================================================
  const underwaterCityGroup = new THREE.Group();
  worldGroup.add(underwaterCityGroup);

  // 在航道与四周水底增设多座带天台管道与密集窗格的沉没摩天楼（还原图3水底壮观的绿色/群青摩天楼群）
  const subSkyscraperSpecs = [
    { x: -14.0, y: -1.1, z: -10.5, w: 7.4, h: 26, d: 7.4, rot: 0.22, col: '#28c4b8' },
    { x: -21.5, y: -3.2, z: -4.2, w: 5.8, h: 24, d: 5.8, rot: -0.15, col: '#1ca2b8' },
    { x: -9.5, y: -4.5, z: -19.5, w: 6.4, h: 24, d: 6.4, rot: 0.35, col: '#1888b2' },
    { x: 11.5, y: -3.8, z: -10.5, w: 6.2, h: 24, d: 6.2, rot: -0.28, col: '#1e9cb4' },
    { x: -8.2, y: -3.6, z: 11.5, w: 6.0, h: 24, d: 6.0, rot: 0.18, col: '#1ca4b8' }
  ];

  subSkyscraperSpecs.forEach((sp) => {
    const bGroup = new THREE.Group();
    bGroup.position.set(sp.x, sp.y, sp.z);
    bGroup.rotation.y = sp.rot;

    const body = new THREE.Mesh(
      new THREE.BoxGeometry(sp.w, sp.h, sp.d),
      makePainterlyMat(sp.col, {}, true)
    );
    body.position.y = -sp.h / 2;
    addEdgeHighlight(body, '#64f5dc', 0.42);
    bGroup.add(body);

    // 还原图3水下摩天楼顶部的女儿墙边框、空调主机房与L型通风管道
    const roofBox1 = new THREE.Mesh(
      new THREE.BoxGeometry(sp.w * 0.32, 1.35, sp.d * 0.32),
      makePainterlyMat('#38dec8', {}, true)
    );
    roofBox1.position.set(sp.w * 0.18, 0.68, -sp.d * 0.15);
    addEdgeHighlight(roofBox1, '#9effeb', 0.5);
    bGroup.add(roofBox1);

    const roofBox2 = new THREE.Mesh(
      new THREE.BoxGeometry(sp.w * 0.28, 0.75, sp.d * 0.22),
      makePainterlyMat('#2cb8b4', {}, true)
    );
    roofBox2.position.set(-sp.w * 0.12, 0.38, sp.d * 0.12);
    bGroup.add(roofBox2);

    underwaterCityGroup.add(bGroup);
  });

  // 构建参考图 3 中最震撼的水下主角：【深海巨鲸（Giant Whale）】在摩天楼峡谷间摆尾巡游
  const whaleGroup = new THREE.Group();
  scene.add(whaleGroup);

  const whaleMat = makePainterlyMat('#062356', {}, true);
  const whaleBellyMat = makePainterlyMat('#16589e', {}, true);

  // 流线型鲸鱼主躯干、前段与3节摆动尾段
  const whaleHead = new THREE.Mesh(new THREE.SphereGeometry(1.35, 14, 12), whaleMat);
  whaleHead.scale.set(1.05, 0.82, 2.2);
  whaleHead.position.set(0, 0, 1.6);
  whaleGroup.add(whaleHead);

  const whaleTorso = new THREE.Mesh(new THREE.SphereGeometry(1.42, 14, 12), whaleMat);
  whaleTorso.scale.set(1.0, 0.85, 2.4);
  whaleTorso.position.set(0, 0, -0.8);
  addEdgeHighlight(whaleTorso, '#2ec4e8', 0.25);
  whaleGroup.add(whaleTorso);

  // 左右修长的胸鳍
  [-1, 1].forEach((side) => {
    const fin = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.14, 0.85), whaleBellyMat);
    fin.position.set(side * 1.85, -0.35, 0.4);
    fin.rotation.y = side * -0.35;
    fin.rotation.z = side * -0.25;
    whaleGroup.add(fin);
  });

  // 铰接式摆动鲸尾与宽大水平尾鳍（Fluke）
  const whaleTailPivot1 = new THREE.Group();
  whaleTailPivot1.position.set(0, 0, -3.2);
  whaleGroup.add(whaleTailPivot1);

  const tailSeg1 = new THREE.Mesh(new THREE.ConeGeometry(0.95, 3.6, 10), whaleMat);
  tailSeg1.rotation.x = -Math.PI / 2;
  tailSeg1.position.z = -1.6;
  whaleTailPivot1.add(tailSeg1);

  const whaleFlukePivot = new THREE.Group();
  whaleFlukePivot.position.set(0, 0, -3.3);
  whaleTailPivot1.add(whaleFlukePivot);

  const flukeMesh = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.14, 1.1), whaleBellyMat);
  flukeMesh.rotation.y = 0.0;
  addEdgeHighlight(flukeMesh, '#52e8ff', 0.35);
  whaleFlukePivot.add(flukeMesh);

  // ============================================================================
  // 7. 手绘风小人（带洒水壶/木槌）与双桨动画系统
  // ============================================================================
  const explorerGroup = new THREE.Group();
  scene.add(explorerGroup);

  const explorerBodyPivot = new THREE.Group();
  explorerGroup.add(explorerBodyPivot);

  const torsoMesh = new THREE.Mesh(
    new THREE.ConeGeometry(0.28, 0.68, 8),
    makePainterlyMat('#ff9b42')
  );
  torsoMesh.position.y = 0.52;
  addEdgeHighlight(torsoMesh, '#ffe099', 0.5);
  explorerBodyPivot.add(torsoMesh);

  const headMesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.21, 12, 12),
    makePainterlyMat('#ffe2c4')
  );
  headMesh.position.y = 0.98;
  explorerBodyPivot.add(headMesh);

  const hatBrim = new THREE.Mesh(
    new THREE.CylinderGeometry(0.38, 0.38, 0.05, 14),
    makePainterlyMat('#f5c84c')
  );
  hatBrim.position.y = 1.12;
  explorerBodyPivot.add(hatBrim);
  const hatCrown = new THREE.Mesh(
    new THREE.CylinderGeometry(0.18, 0.22, 0.16, 12),
    makePainterlyMat('#e69d32')
  );
  hatCrown.position.y = 1.2;
  explorerBodyPivot.add(hatCrown);

  const leftArmPivot = new THREE.Group();
  leftArmPivot.position.set(-0.24, 0.72, 0);
  const leftArm = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.38, 0.11), makePainterlyMat('#ff9b42'));
  leftArm.position.y = -0.16;
  leftArmPivot.add(leftArm);
  explorerBodyPivot.add(leftArmPivot);

  const rightArmPivot = new THREE.Group();
  rightArmPivot.position.set(0.24, 0.72, 0);
  const rightArm = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.38, 0.11), makePainterlyMat('#ff9b42'));
  rightArm.position.y = -0.16;
  rightArmPivot.add(rightArm);

  // 园艺水壶与施工木槌组合工具
  const toolGroup = new THREE.Group();
  toolGroup.position.set(0, -0.34, 0.14);
  toolGroup.visible = false;
  const wateringCan = new THREE.Mesh(
    new THREE.CylinderGeometry(0.14, 0.16, 0.26, 10),
    makePainterlyMat('#48e5c2')
  );
  toolGroup.add(wateringCan);
  const spout = new THREE.Mesh(
    new THREE.CylinderGeometry(0.03, 0.05, 0.28, 6),
    makePainterlyMat('#48e5c2')
  );
  spout.rotation.x = Math.PI / 3;
  spout.position.set(0, 0.05, 0.2);
  toolGroup.add(spout);
  rightArmPivot.add(toolGroup);
  explorerBodyPivot.add(rightArmPivot);

  const leftLegPivot = new THREE.Group();
  leftLegPivot.position.set(-0.11, 0.24, 0);
  const leftLeg = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.28, 0.11), makePainterlyMat('#3b4d7a'));
  leftLeg.position.y = -0.12;
  leftLegPivot.add(leftLeg);
  explorerBodyPivot.add(leftLegPivot);

  const rightLegPivot = new THREE.Group();
  rightLegPivot.position.set(0.11, 0.24, 0);
  const rightLeg = new THREE.Mesh(new THREE.BoxGeometry(0.11, 0.28, 0.11), makePainterlyMat('#3b4d7a'));
  rightLeg.position.y = -0.12;
  rightLegPivot.add(rightLeg);
  explorerBodyPivot.add(rightLegPivot);

  const characterDetail = refineCharacter(THREE, { explorerBodyPivot, torsoMesh, headMesh, hatBrim, hatCrown, leftArmPivot, rightArmPivot, leftLegPivot, rightLegPivot });

  const leftOarPivot = new THREE.Group();
  leftOarPivot.position.set(-0.92, 0.56, 0.1);
  leftOarPivot.visible = false;
  const oarShaftGeo = new THREE.CylinderGeometry(0.035, 0.035, 2.1, 6);
  oarShaftGeo.rotateZ(Math.PI / 2);
  const oarMat = makePainterlyMat('#d97d3e');
  const leftOarMesh = new THREE.Mesh(oarShaftGeo, oarMat);
  leftOarMesh.position.x = -0.75;
  leftOarMesh.rotation.z = 0.38;
  leftOarPivot.add(leftOarMesh);
  boatMeshGroup.add(leftOarPivot);

  const rightOarPivot = new THREE.Group();
  rightOarPivot.position.set(0.92, 0.56, 0.1);
  rightOarPivot.visible = false;
  const rightOarMesh = new THREE.Mesh(oarShaftGeo, oarMat);
  rightOarMesh.position.x = 0.75;
  rightOarMesh.rotation.z = -0.38;
  rightOarPivot.add(rightOarMesh);
  boatMeshGroup.add(rightOarPivot);

  // ============================================================================
  // 8. 各种植园与区域修缮点（在建造/播种过程中，植物与模型实时动态生长！）
  // ============================================================================
  // ============================================================================
  // 7.5 区块注册表（zones.js）——海面每块水域的功能、可站立区域、上岸点、停泊位
  // ============================================================================
  // 这里不再写任何区块坐标：增删区块、搬动地块、改上岸点都只改 zones.js。
  const WALK_REGIONS = zones.walkRegions;

  // 脚底高度永远跟着模型走：在区块配置的高度窗口里取最高的可站立水平面。
  // 配置里的 y 只是设计意图，模型改了、道具挪了也不会再出现悬空或陷进木板。
  let standProbeMeshes = null;
  const standRay = new THREE.Raycaster();
  const STAND_DOWN = new THREE.Vector3(0, -1, 0);
  const standNormalMatrix = new THREE.Matrix3();
  const standProbePoint = new THREE.Vector3();
  const standFaceNormal = new THREE.Vector3();

  function standProbeList() {
    if (standProbeMeshes) return standProbeMeshes;
    const list = [];
    scene.updateMatrixWorld(true);
    scene.traverse((o) => {
      if (!o.isMesh || o === waterPlane || o.name === 'cartoon-water') return;
      for (let p = o; p; p = p.parent) {
        if (!p.visible || p === boatAnchorGroup || p === explorerGroup) return;
      }
      list.push(o);
    });
    standProbeMeshes = list;
    return list;
  }

  function sampleStandHeight(x, z, lo, hi) {
    standRay.set(standProbePoint.set(x, 60, z), STAND_DOWN);
    standRay.far = 120;
    let best = null;
    for (const hit of standRay.intersectObjects(standProbeList(), false)) {
      if (!hit.face) continue;
      const y = hit.point.y;
      if (y <= WATER_LEVEL + 0.02 || y < lo || y > hi) continue;
      standNormalMatrix.getNormalMatrix(hit.object.matrixWorld);
      standFaceNormal.copy(hit.face.normal).applyMatrix3(standNormalMatrix).normalize();
      if (standFaceNormal.y < 0.7) continue;
      if (best === null || y > best) best = y;
    }
    return best;
  }

  function regionStandHeight(region, x, z) {
    if (!region) return null;
    const [lo, hi] = region.span;
    return sampleStandHeight(x, z, lo, hi);
  }

  // 走到哪儿就把脚放哪儿；找不到支撑面时保持当前高度（不往下掉）。
  let lastSettle = null;
  function settleFootY(group, region) {
    const y = regionStandHeight(region, group.position.x, group.position.z);
    lastSettle = { x: +group.position.x.toFixed(2), z: +group.position.z.toFixed(2), region: region?.id || null, sampled: y, prev: +group.position.y.toFixed(2) };
    if (y !== null) group.position.y = y;
    return y;
  }

  // 行走时每 ~14Hz 采一次脚底，避免每帧对整场景做射线。
  let footProbeClock = 0;
  function settleFootThrottled(group, region, dt) {
    footProbeClock += dt;
    if (footProbeClock < 0.07) return;
    footProbeClock = 0;
    settleFootY(group, region);
  }

  function walkFootRegion() {
    return WALK_REGIONS.find((item) => item.id === state.walkRegionId)
      || WALK_REGIONS.find((item) => item.zone === state.currentZone && item.contains(explorerGroup.position))
      || null;
  }

  function getWalkRegionAt(point) {
    const region = WALK_REGIONS.find((item) => item.zone === state.currentZone && item.contains(point));
    if (!region) return null;
    // 矩形内没有真实地面（水面、空中）就不算可走区域。
    return regionStandHeight(region, point.x, point.z) === null ? null : region;
  }

  function isWalkSegmentClear(from, to, region) {
    const distance = Math.hypot(to.x - from.x, to.z - from.z);
    const samples = Math.max(2, Math.ceil(distance / .35));
    for (let i = 1; i <= samples; i++) {
      const t = i / samples;
      const probe = new THREE.Vector3(
        THREE.MathUtils.lerp(from.x, to.x, t), region.y,
        THREE.MathUtils.lerp(from.z, to.z, t)
      );
      if (!region.contains(probe)) return false;
    }
    return true;
  }

  const homeZone = zones.get('zone1');
  boatAnchorGroup.position.copy(homeZone.boatPark);
  boatAnchorGroup.rotation.y = homeZone.boatYaw;
  explorerGroup.position.copy(homeZone.landStand);
  explorerGroup.rotation.y = -0.6;

  // 再拉远一档的默认俯视镜头偏移 & 航行时的远景俯瞰跟随偏移
  const CAM_OFFSET = new THREE.Vector3(-54, 76.37, 54);
  const BOAT_FOLLOW_OFFSET = new THREE.Vector3(-54, 76.37, 54);
  const WORKER_FOCUS_OFFSET = new THREE.Vector3(-35, 49.5, 35);
  let cameraDistanceScale = 1.0;
  let isApplyingCameraLock = false;
  let isUserZooming = false;

  const state = {
    coins: 80,
    wood: 0,
    parts: 0,
    seeds: 3,
    food: 0,
    fish: 0,
    pearl: 0,
    shipLevel: 1,
    farSeaUnlocked: false,
    salvageRuns: 0,
    salvageCooldown: 0,
    currentZone: 'zone1', // 'zone1' | 'zone2' | 'zone3'
    workerMode: 'IDLE_ASHORE',
    activeJobSite: null,
    targetZone: 'zone1',
    jobProgress: 0,
    transitionT: 0,
    jumpStartPos: new THREE.Vector3(),
    jumpEndPos: new THREE.Vector3(),
    walkTargetPos: new THREE.Vector3(),
    walkRegionId: null,
    sailCurve: null,
    sailProgress: 0,
    sailDuration: 5.5,
    sailTargetPos: null,
    sailIntent: null,
    // 当前所在（或正前往）的上岸点 id：主码头是 'main'，独立平台各自一个。
    landingId: 'main',
    pendingWorldTarget: null,
    boatBlockers: null, // 船体高度带内的实体包围盒，航行开始时重建（见 collectSolidRects）
    camLockMode: 'zone1',
    focusWorkerUntil: 0,
    manualCamera: false
  };

  // economy.busy 的口径是「人不在岸上待机」——拿它拦航行会把「已经在船上」也算成忙，
  // 结果是在船上点目的地、点上岸桩、点物资全部没反应（看起来就像寻路卡死）。
  // 这里只拦真正在进行的施工 / 加工。
  function workInProgress() {
    return Boolean(state.activeJobSite) || state.workerMode === 'BUILDING' || state.workerMode === 'CRAFTING';
  }

  function focusCameraOnWorker() {
    state.manualCamera = false;
    if (state.workerMode === 'ROWING' || state.workerMode === 'BOARDING') {
      state.camLockMode = 'boat';
      return;
    }
    state.camLockMode = 'worker';
    state.focusWorkerUntil = performance.now() + 4200;
    closeActionMenus();
  }

  // 为【横滨铁道站台】预创建 3 阶段可种植与建造生长模型
  const z2CropStage1 = new THREE.Group();
  z2CropStage1.visible = false;
  stationPlatformGroup.add(z2CropStage1);
  {
    // 在混凝土站台上开辟木框种植箱并种出翠绿芭蕉叶与向日葵
    const planterBox = new THREE.Mesh(
      new THREE.BoxGeometry(4.8, 0.38, 1.8),
      makePainterlyMat('#c8763e')
    );
    planterBox.position.set(-1.2, 0.45, 0.8);
    addEdgeHighlight(planterBox, '#ffcf88', 0.55);
    z2CropStage1.add(planterBox);

    const p1 = createTropicalPlantCluster(0.95, true, '#ffcf48');
    p1.position.set(-2.4, 0.6, 0.8);
    z2CropStage1.add(p1);

    const p2 = createTropicalPlantCluster(1.05, true, '#ff7898');
    p2.position.set(0.0, 0.6, 0.8);
    z2CropStage1.add(p2);
  }

  const z2CropStage2 = new THREE.Group();
  z2CropStage2.visible = false;
  zone2Root.add(z2CropStage2);
  {
    // 在蓝白电车车顶培育空中花园藤蔓，并点亮电车暖黄车厢灯
    const trainGarden = createTropicalPlantCluster(1.25, true, '#ffe252');
    trainGarden.position.set(4.5, WATER_LEVEL + 3.5, -3.2);
    z2CropStage2.add(trainGarden);

    const roofBush = createTropicalPlantCluster(1.0, true, '#74ffea');
    roofBush.position.set(3.8, WATER_LEVEL + 3.45, -5.2);
    z2CropStage2.add(roofBush);
  }

  const z2CropStage3 = new THREE.Group();
  z2CropStage3.visible = false;
  zone2Root.add(z2CropStage3);
  {
    // 在铁道水道培育发光睡莲花海与召唤更多水母群
    for (let i = 0; i < 6; i++) {
      const lotus = new THREE.Mesh(
        new THREE.ConeGeometry(0.32, 0.42, 7),
        new THREE.MeshBasicMaterial({ color: i % 2 === 0 ? '#ff88c2' : '#ffe875' })
      );
      lotus.position.set(-3.2 + i * 1.1, WATER_LEVEL + 0.22, -3.8 + (i % 2) * 1.4);
      z2CropStage3.add(lotus);
    }
    createGlowingJellyfish(z2CropStage3, -1.2, WATER_LEVEL - 0.15, -1.8, 1.1);
    createGlowingJellyfish(z2CropStage3, 1.5, WATER_LEVEL - 0.2, 2.8, 0.9);
  }

  // 为【西南天台卫星锅种植园（参考图2）】预创建 2 阶段可种植热带作物模型
  const z3CropStage1 = new THREE.Group();
  z3CropStage1.visible = false;
  zone3Root.add(z3CropStage1);
  {
    const c1 = createTropicalPlantCluster(1.3, true, '#ffcf48');
    c1.position.set(1.6, WATER_LEVEL + 1.7, -1.5);
    z3CropStage1.add(c1);

    const c2 = createTropicalPlantCluster(1.2, true, '#ff6b8b');
    c2.position.set(0.2, WATER_LEVEL + 1.7, -2.1);
    z3CropStage1.add(c2);
  }

  const z3CropStage2 = new THREE.Group();
  z3CropStage2.visible = false;
  zone3Root.add(z3CropStage2);
  {
    // 丰茂的巨型芭蕉树林与悬挂彩灯藤架
    const c3 = createTropicalPlantCluster(1.55, true, '#5efad2');
    c3.position.set(-1.8, WATER_LEVEL + 1.75, 1.8);
    z3CropStage2.add(c3);

    const c4 = createTropicalPlantCluster(1.4, true, '#ffe66d');
    c4.position.set(2.1, WATER_LEVEL + 1.75, 1.6);
    z3CropStage2.add(c4);
  }

  const houseGroupRef = worldGroup.children.find(
    (ch) => ch.position && Math.abs(ch.position.x - 4.3) < 0.2 && Math.abs(ch.position.z - -0.4) < 0.2
  );

  const buildSites = [
    {
      id: 'yokohama_station',
      zone: 'zone2',
      name: '横滨沉没铁道 · 站台与电车园圃',
      // 只命中站台建筑本体，不把整片铁路、路基和周边水面算进交互区域。
      hitRoots: [stationPlatformGroup, trainCarGroup],
      hoverAnchor: zones.get('zone2').hoverAnchor.clone(),
      boatParkPos: zones.get('zone2').boatPark,
      shoreEdgePos: zones.get('zone2').dockEdge,
      buildStandPos: zones.get('zone2').landStand,
      level: 0,
      maxLevel: 3,
      storedCoins: 0,
      coinsPerCycle: 0,
      stages: [
        {
          btnText: '🚣 划船去站台种植向日葵花圃 (20 🐚 + 2 🪵)',
          localBtnText: '🌱 在铁道站台播种向日葵花圃 (20 🐚 + 2 🪵)',
          desc: '小人划船前往横滨铁道道口，登岸在混凝土高架站台上开辟木框花床并种下芭蕉与向日葵。需要 2 份木料钉花箱。',
          cost: 20,
          materials: { wood: 2 },
          rateAdd: 2,
          applyVisual(progress) {
            z2CropStage1.visible = true;
            z2CropStage1.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去电车顶培育空中花园 (40 🐚 + 3 ⚙)',
          localBtnText: '🌿 在复古电车顶种植藤蔓花海 (40 🐚 + 3 ⚙)',
          desc: '在半淹没的蓝白复古电车车顶培育翠绿热带植物丛与鲜花，让沉没铁道焕发生机。需要 3 个旧零件加固车顶棚架。',
          cost: 40,
          materials: { parts: 3 },
          rateAdd: 3,
          applyVisual(progress) {
            z2CropStage2.visible = true;
            z2CropStage2.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去水道培育发光睡莲与水母 (65 🐚 + 3 🪵 + 2 ⚙)',
          localBtnText: '🪷 培育铁道发光睡莲与水母群 (65 🐚 + 3 🪵 + 2 ⚙)',
          desc: '在枕木水道间播撒发光睡莲，吸引透明发光水母环绕道口游弋。需要木料与旧零件固定浮床。',
          cost: 65,
          materials: { wood: 3, parts: 2 },
          rateAdd: 5,
          applyVisual(progress) {
            z2CropStage3.visible = true;
            z2CropStage3.scale.setScalar(Math.max(0.05, progress));
          }
        }
      ]
    },
    {
      id: 'rooftop_planter',
      zone: 'zone3',
      name: '圆弧屋顶农场',
      // 只命中天台种植建筑与屋顶花池，不把整片邻近区域算进交互范围。
      hitRoots: [zone3Root],
      hoverAnchor: zones.get('zone3').hoverAnchor.clone(),
      boatParkPos: zones.get('zone3').boatPark,
      shoreEdgePos: zones.get('zone3').dockEdge,
      buildStandPos: zones.get('zone3').landStand,
      level: 0,
      maxLevel: 2,
      storedCoins: 0,
      coinsPerCycle: 0,
      stages: [
        {
          btnText: '🚣 划船去天台花池种植龟背竹 (25 🐚 + 2 🪵)',
          localBtnText: '🌱 浇水种植大叶龟背竹与花丛 (25 🐚 + 2 🪵)',
          desc: '划向圆弧农场，在圆弧屋顶的木框土槽里种满大叶龟背竹。需要 2 份木料修补土槽。',
          cost: 25,
          materials: { wood: 2 },
          rateAdd: 3,
          applyVisual(progress) {
            z3CropStage1.visible = true;
            z3CropStage1.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去扩建天台巨叶芭蕉林 (50 🐚 + 2 🪵)',
          localBtnText: '🌴 培育丰茂芭蕉林与翡翠花果 (50 🐚 + 2 🪵)',
          desc: '悉心浇灌整座屋顶花坛，让翠绿宽大的热带芭蕉叶与花朵铺满天台。需要木料加高围栏。',
          cost: 50,
          materials: { wood: 2 },
          rateAdd: 4,
          applyVisual(progress) {
            z3CropStage2.visible = true;
            z3CropStage2.scale.setScalar(Math.max(0.05, progress));
          }
        }
      ]
    },
    {
      id: 'home_cabin',
      zone: 'zone1',
      name: 'sea · 太阳能木屋花圃',
      // 只命中太阳能木屋本体；船仍由独立的 boatMeshGroup 负责交互。
      hitRoots: [houseGroupRef || boatMeshGroup],
      hoverAnchor: zones.get('zone1').hoverAnchor.clone(),
      boatParkPos: zones.get('zone1').boatPark,
      shoreEdgePos: zones.get('zone1').dockEdge,
      buildStandPos: zones.get('zone1').landStand,
      level: 1,
      maxLevel: 2,
      storedCoins: 0,
      coinsPerCycle: 1,
      stages: [
        {},
        {
          btnText: '🚣 划船回木屋种花与挂灯 (20 🐚 + 2 🪵)',
          localBtnText: '🌱 在木屋码头种花并点亮暖灯 (20 🐚 + 2 🪵)',
          desc: '在起始木屋码头种植水上盆栽花丛，并点亮暖黄航标灯笼。需要 2 份木料搭花箱。',
          cost: 20,
          materials: { wood: 2 },
          rateAdd: 2,
          applyVisual(progress) {
            if (!this._plantGroup) {
              this._plantGroup = createTropicalPlantCluster(0.9, true, '#ff9452');
              this._plantGroup.position.set(2.2, 2.0, 2.4);
              worldGroup.add(this._plantGroup);
            }
            this._plantGroup.scale.setScalar(Math.max(0.05, progress * 0.9));
          }
        }
      ]
    }
  ];

  const economy = createEconomy(state, id => buildSites.find(site => site.id === id)?.level || 0);
  let economyView = null;

  // ============================================================================
  // 8.5 居民与生活反馈：木屋升到 Lv.2 后，码头出现住户，窗内与挂灯亮起暖光
  // ============================================================================
  const homeSite = buildSites.find((s) => s.id === 'home_cabin');

  function createResidentFigure() {
    const group = new THREE.Group();
    const bodyPivot = new THREE.Group();
    group.add(bodyPivot);

    const dressMat = makePainterlyMat('#6fc3a8');
    const apronMat = makePainterlyMat('#f7ead0');
    const skinMat = makePainterlyMat('#ffe2c4');
    const hairMat = makePainterlyMat('#3c3550');
    const bootMat = makePainterlyMat('#38506e');

    const skirt = new THREE.Mesh(new THREE.ConeGeometry(0.26, 0.62, 8), dressMat);
    skirt.position.y = 0.49;
    addEdgeHighlight(skirt, '#c8f5e4', 0.45);
    bodyPivot.add(skirt);

    const apron = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.34, 0.04), apronMat);
    apron.position.set(0, 0.44, 0.18);
    bodyPivot.add(apron);

    const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 12, 12), skinMat);
    head.position.y = 0.92;
    bodyPivot.add(head);

    const hair = new THREE.Mesh(
      new THREE.SphereGeometry(0.175, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.58),
      hairMat
    );
    hair.position.y = 0.95;
    hair.rotation.x = -0.25;
    bodyPivot.add(hair);

    const bun = new THREE.Mesh(new THREE.SphereGeometry(0.085, 8, 8), hairMat);
    bun.position.set(0, 1.05, -0.11);
    bodyPivot.add(bun);

    const arms = [-1, 1].map((side) => {
      const pivot = new THREE.Group();
      pivot.position.set(side * 0.19, 0.72, 0);
      const arm = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.34, 0.09), dressMat);
      arm.position.y = -0.15;
      pivot.add(arm);
      const hand = new THREE.Mesh(new THREE.SphereGeometry(0.055, 8, 8), skinMat);
      hand.position.y = -0.32;
      pivot.add(hand);
      bodyPivot.add(pivot);
      return pivot;
    });

    [-1, 1].forEach((side) => {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.24, 0.09), bootMat);
      leg.position.set(side * 0.09, 0.14, 0);
      bodyPivot.add(leg);
    });

    return { group, bodyPivot, head, arms };
  }

  const resident = createResidentFigure();
  if (houseGroupRef) {
    // 站在码头木板前端、屋檐投影之外，俯视镜头才能看见她。
    resident.group.position.set(0.9, 0.67, 4.55);
    resident.group.rotation.y = -0.12;
    houseGroupRef.add(resident.group);
  } else {
    resident.group.position.set(4.9, 2.15, 3.0);
    worldGroup.add(resident.group);
  }
  resident.group.visible = false;
  resident.group.scale.setScalar(0.001);

  // 窗内暖光与灯笼光晕：俯视构图下用朝向镜头的柔光精灵，避免被屋檐完全遮住。
  function createWarmGlowTexture() {
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const ctx = c.getContext('2d');
    const grad = ctx.createRadialGradient(32, 32, 2, 32, 32, 31);
    grad.addColorStop(0, 'rgba(255, 231, 178, 1)');
    grad.addColorStop(0.42, 'rgba(255, 196, 128, 0.52)');
    grad.addColorStop(1, 'rgba(255, 170, 96, 0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 64, 64);
    return new THREE.CanvasTexture(c);
  }
  const warmGlowTexture = createWarmGlowTexture();
  const windowGlowMat = new THREE.SpriteMaterial({
    map: warmGlowTexture,
    color: '#ffe3ae',
    transparent: true,
    opacity: 0.9,
    depthWrite: false,
    blending: THREE.AdditiveBlending
  });
  const windowGlow = new THREE.Sprite(windowGlowMat);
  windowGlow.scale.set(1.9, 1.35, 1);
  const lifeDetails = new THREE.Group();
  lifeDetails.visible = false;
  (houseGroupRef || worldGroup).add(lifeDetails);
  // 暖光落在木屋门前的码头上，俯视构图也能看到“屋里有人点了灯”。
  windowGlow.position.set(0.35, 1.02, 3.05);
  lifeDetails.add(windowGlow);

  // 码头挂灯：一根短杆垂下一盏暖黄小灯。
  const lanternGroup = new THREE.Group();
  lanternGroup.position.set(2.4, 1.15, 4.8);
  const lanternRod = new THREE.Mesh(
    new THREE.CylinderGeometry(0.02, 0.02, 0.44, 6),
    makePainterlyMat('#6b4a34')
  );
  lanternRod.position.y = 0.22;
  lanternGroup.add(lanternRod);
  const lanternMat = new THREE.MeshBasicMaterial({ color: '#ffcf7a' });
  const lanternBulb = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 10), lanternMat);
  lanternBulb.position.y = -0.02;
  lanternGroup.add(lanternBulb);
  const lanternCap = new THREE.Mesh(
    new THREE.ConeGeometry(0.15, 0.12, 8),
    makePainterlyMat('#c26a3d')
  );
  lanternCap.position.y = 0.12;
  lanternGroup.add(lanternCap);
  const lanternGlowMat = new THREE.SpriteMaterial({
    map: warmGlowTexture,
    color: '#ffd08a',
    transparent: true,
    opacity: 0.75,
    depthWrite: false,
    blending: THREE.AdditiveBlending
  });
  const lanternGlow = new THREE.Sprite(lanternGlowMat);
  lanternGlow.scale.set(1.05, 1.05, 1);
  lanternGlow.position.y = -0.02;
  lanternGroup.add(lanternGlow);
  lifeDetails.add(lanternGroup);

  let residentScale = 0;
  let residentArrived = false;
  function updateResidentLife(t, dt) {
    const shouldLive = homeSite.level >= 2;
    residentScale += ((shouldLive ? 1 : 0) - residentScale) * Math.min(1, dt * 5);
    if (!shouldLive && residentScale < 0.01) residentScale = 0;
    const alive = residentScale > 0.01;
    resident.group.visible = alive;
    lifeDetails.visible = alive;
    if (!alive) return;

    resident.group.scale.setScalar(Math.max(0.001, residentScale * 1.12));
    if (!residentArrived) {
      residentArrived = true;
      const anchor = resident.group.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 1.7, 0));
      spawnFloatTip(anchor, '🏡 居民入住');
    }

    resident.bodyPivot.position.y = Math.sin(t * 1.7) * 0.012;
    resident.bodyPivot.rotation.z = Math.sin(t * 0.8) * 0.02;
    resident.head.rotation.y = Math.sin(t * 0.45) * 0.28;
    const wavePhase = t % 9;
    resident.arms[1].rotation.z = wavePhase < 1.8
      ? -2.15 + Math.sin(t * 9) * 0.28
      : Math.sin(t * 1.3) * 0.06;
    resident.arms[0].rotation.z = -Math.sin(t * 1.1) * 0.05;
    windowGlowMat.opacity = 0.82 + Math.sin(t * 1.9) * 0.1;
    lanternGlowMat.opacity = 0.66 + Math.sin(t * 2.4 + 1.1) * 0.12;
    lanternMat.color.setHSL(0.09, 0.85, 0.62 + Math.sin(t * 2.4) * 0.04);
  }

  const elCoinVal = document.getElementById('min-coin-val');
  const elWoodVal = document.getElementById('min-wood-val');
  const elPartsVal = document.getElementById('min-parts-val');
  const elCoinRate = document.getElementById('min-coin-rate');
  const elWorkerStatus = document.getElementById('worker-status-text');

  function syncCoinUI() {
    elCoinVal.textContent = Math.floor(state.coins);
    elWoodVal.textContent = `🪵 ${state.wood}`;
    elPartsVal.textContent = `⚙ ${state.parts}`;
    const shipEl = document.getElementById('min-ship-val');
    if (shipEl) shipEl.textContent = `⛵ ${state.shipLevel}`;
    for (const [key, short] of [['seeds', '种'], ['food', '食'], ['fish', '鱼'], ['pearl', '珠']]) {
      const el = document.getElementById(`min-${key}-val`);
      el.textContent = `${short} ${state[key]}`;
    }
    for (const key of ['wood', 'parts', 'seeds', 'food', 'fish', 'pearl']) {
      const el = document.getElementById(`min-${key}-val`);
      const label = `${MATERIALS[key].name} ${state[key]}/${MATERIALS[key].capacity}；${MATERIALS[key].source}`;
      el.title = label;
      el.setAttribute('aria-label', label);
    }
    elCoinRate.textContent = '';
  }

  function setWorkerStatus(text) {
    elWorkerStatus.textContent = text;
  }

  function awardResource(resource, amount, anchor, label) {
    if (!economy.receive({ [resource]: amount })) return false;
    syncCoinUI();
    if (anchor) spawnResourceFlight(anchor, { [resource]: amount });
    else spawnFloatTip(explorerGroup.position.clone().add(new THREE.Vector3(0, 1.8, 0)), `+${amount} ${label}`);
    return true;
  }

  function updateObjectiveUI() {
    const farSea = destinationWheel.querySelector('[data-zone="zone4"]');
    farSea.disabled = !state.farSeaUnlocked;
    farSea.setAttribute('aria-disabled', String(!state.farSeaUnlocked));
  }

  // 打捞是冷却式产出，而不是一次性清空：绞盘每 40 秒从水道里拖上一捆漂流物（3 木料 + 2 旧零件）。
  // 20 分钟 Demo 内约可打捞 30 次，足够覆盖全部建设与船只改造，同时保留“要等一会儿”的节奏。
  const SALVAGE_COOLDOWN = 40;
  const SALVAGE_YIELD = { wood: 3, parts: 2 };

  function getSalvageCooldownLeft() {
    return Math.max(0, state.salvageCooldown || 0);
  }

  function isSalvageReady() {
    return getSalvageCooldownLeft() <= 0;
  }

  function performSalvage() {
    // 打捞台属于哪个区块由 zones.js 的 harbor 配置决定，不在代码里写死 zone1。
    if (economy.busy || !zones.serviceZones('salvage').includes(state.currentZone)) return false;
    const spot = zones.harborPoint('salvage') || new THREE.Vector3(-12, WATER_LEVEL, 13);
    const anchor = spot.clone().add(new THREE.Vector3(0, 4, 0));
    const left = getSalvageCooldownLeft();
    if (left > 0) {
      spawnFloatTip(anchor, `绞盘冷却中 · ${Math.ceil(left)} 秒`);
      return false;
    }
    if (!economy.receive(SALVAGE_YIELD)) {
      spawnFloatTip(anchor, '材料仓满：先建造消耗木料或旧零件');
      return false;
    }
    state.salvageRuns += 1;
    state.salvageCooldown = SALVAGE_COOLDOWN;
    spawnResourceFlight(anchor, SALVAGE_YIELD);
    syncCoinUI();
    return true;
  }

  function upgradeShip() {
    const result = economy.upgradeShip();
    if (!result.ok) {
      economyView?.open('ship');
      return false;
    }
    boatMeshGroup.scale.set(1.12, 1.08, 1.16);
    boatMeshGroup.position.y = 0.08;
    syncCoinUI();
    spawnFloatTip(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 2.4, 0)), '⛵ 2');
    updateObjectiveUI();
    return true;
  }

  // ============================================================================
  // 9. 精确 3D Mesh Raycast 悬停检测（鼠标移到模型上才显示，移开立刻消失）
  // ============================================================================
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let hoveredTarget = null;
  let hideCardTimer = null;
  let harborTargets = { salvage: null, dock: null };

  function registerHarborTargets(targets) {
    harborTargets = { salvage: targets.salvage || null, dock: targets.dock || null };
    buildSalvageGauge();
    if (!economyView) economyView = createEconomyView({
      THREE, worldGroup, camera, state, economy, buildSites, activateSite, zones,
      travel: startSailBetweenZones, upgradeShip, performSalvage, syncUI: syncCoinUI,
      notify: message => spawnFloatTip(explorerGroup.position.clone(), message)
    });
  }

  // 绞盘充能指示：平台上一圈会转的暖色环。
  // 就绪时缓慢旋转并轻轻呼吸（邀请点击）；冷却时停在原处、由小长大逐渐补齐（看得见“快好了”）。
  let salvageGauge = null;
  function buildSalvageGauge() {
    if (salvageGauge || !harborTargets.salvage) return;
    const group = new THREE.Group();
    group.name = 'salvage-cooldown-gauge';
    // 停在绞盘平台靠水一侧，避开木箱与栈板，俯视时不被遮挡。
    group.position.set(-0.8, 1.4, 1.15);

    const ringMat = new THREE.MeshBasicMaterial({
      color: '#ffd479',
      transparent: true,
      opacity: 0.95,
      depthWrite: false,
      side: THREE.DoubleSide
    });
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.5, 0.66, 32, 1), ringMat);
    ring.rotation.x = -Math.PI / 2;
    group.add(ring);

    // 外侧细亮圈强化轮廓，避免和木板颜色糊在一起。
    const rimMat = new THREE.MeshBasicMaterial({
      color: '#fff3cf',
      transparent: true,
      opacity: 0.8,
      depthWrite: false,
      side: THREE.DoubleSide
    });
    const rim = new THREE.Mesh(new THREE.RingGeometry(0.72, 0.76, 32, 1), rimMat);
    rim.rotation.x = -Math.PI / 2;
    group.add(rim);

    // 内侧暖色圆盘（半径 1，靠缩放表示充能进度），像绞盘的充能刻度。
    const coreMat = new THREE.MeshBasicMaterial({
      color: '#ffcf7a',
      transparent: true,
      opacity: 0.7,
      depthWrite: false
    });
    const pip = new THREE.Mesh(new THREE.CircleGeometry(1, 28), coreMat);
    pip.rotation.x = -Math.PI / 2;
    pip.position.y = 0.004;
    pip.scale.setScalar(0.02);
    group.add(pip);

    // 深色轮毂垫在暖色圆盘下面，让亮部有对比、读作“绞盘刻度盘”而不是一滩光。
    const hubMat = new THREE.MeshBasicMaterial({
      color: '#4a3a2b',
      transparent: true,
      opacity: 0.5,
      depthWrite: false
    });
    const hub = new THREE.Mesh(new THREE.CircleGeometry(0.48, 28), hubMat);
    hub.rotation.x = -Math.PI / 2;
    group.add(hub);

    const glowMat = new THREE.SpriteMaterial({
      map: warmGlowTexture,
      color: '#ffd79a',
      transparent: true,
      opacity: 0.55,
      depthWrite: false,
      blending: THREE.AdditiveBlending
    });
    const glow = new THREE.Sprite(glowMat);
    glow.scale.set(2.2, 2.2, 1);
    glow.position.y = 0.14;
    group.add(glow);

    harborTargets.salvage.add(group);
    salvageGauge = { group, ring, ringMat, rimMat, pip, coreMat, glowMat, spin: 0 };
  }

  function updateSalvageGauge(t) {
    if (!salvageGauge) return;
    const total = SALVAGE_COOLDOWN;
    const left = getSalvageCooldownLeft();
    const charged = total > 0 ? 1 - Math.min(1, left / total) : 1;
    const ready = left <= 0;

    // 环始终保持满尺寸（缩小会直接看不见），用冷暖与亮度区分可打捞/冷却中。
    salvageGauge.ringMat.color.set(ready ? '#ffd479' : '#8fb0b6');
    salvageGauge.rimMat.color.set(ready ? '#fff3cf' : '#cbe0e2');
    salvageGauge.ringMat.opacity = ready ? 0.86 + Math.sin(t * 2.2) * 0.1 : 0.62;
    salvageGauge.rimMat.opacity = ready ? 0.72 + Math.sin(t * 2.2) * 0.1 : 0.4;

    // 内侧暖色圆盘随冷却从 0 长到内径，就是“充能进度条”。
    const fill = ready ? 1 : charged;
    salvageGauge.pip.scale.setScalar(0.02 + fill * 0.46);
    salvageGauge.coreMat.opacity = ready ? 0.72 : 0.3 + charged * 0.3;
    salvageGauge.glowMat.opacity = ready ? 0.22 + Math.sin(t * 2.2) * 0.06 : 0.02;

    // 就绪时缓慢转动表示“可用”，冷却时停在最后角度。
    if (ready) salvageGauge.spin = t * 0.55;
    salvageGauge.ring.rotation.z = salvageGauge.spin;
  }

  // 只读快照用 getter，避免外部拿到初始化时的 null。
  const salvageApi = {
    cooldownDuration: SALVAGE_COOLDOWN,
    yield: SALVAGE_YIELD,
    get cooldown() { return getSalvageCooldownLeft(); },
    get ready() { return isSalvageReady(); },
    get runs() { return state.salvageRuns; },
    get gauge() { return salvageGauge; }
  };

  function requestHarborAction(kind) {
    const ashoreHere = state.workerMode === 'IDLE_ASHORE' && zones.serviceZones(kind).includes(state.currentZone);
    if (kind === 'salvage' && ashoreHere) return performSalvage();
    if (kind === 'dock' && ashoreHere) {
      economyView?.open('ship');
      return true;
    }
    if (!isBoatMode()) return false;
    const target = (zones.harborPoint(kind) || homeZone.boatPark).clone();
    target.y = WATER_LEVEL;
    state.pendingWorldTarget = { type: kind };
    state.activeJobSite = null;
    state.targetZone = state.currentZone;
    state.sailIntent = 'target';
    state.sailTargetPos = target;
    state.sailCurve = buildSmoothSailCurve(state.currentZone, state.currentZone, target);
    state.sailProgress = 0;
    state.sailDuration = Math.max(2, state.sailCurve.getLength() / 3.6);
    state.workerMode = 'ROWING';
    state.camLockMode = 'boat';
    return true;
  }

  // —— 上岸桩与漂浮物资 ——
  // 上岸桩由 harbor-layout 在每个上岸点建好（一个区块可能有多根），这里只登记引用并负责点击路由。
  let landingTargets = {};

  // 每个上岸点水面上立一个 ⚓️ 图标：它是「从这里走上这片区域」的唯一入口。
  // 键是 `zone`（主码头）或 `zone:landingId`（独立平台）。
  const landingMarkers = new Map();
  const landingAnchor = new THREE.Vector3();
  const landingProjected = new THREE.Vector3();

  function splitLandingKey(key) {
    const [zone, landing = 'main'] = String(key).split(':');
    return { zone, landing };
  }

  function ensureLandingMarker(key) {
    const existing = landingMarkers.get(key);
    if (existing) return existing;
    const { zone, landing } = splitLandingKey(key);
    const el = document.createElement('button');
    el.type = 'button';
    el.className = 'landing-marker';
    el.dataset.landingZone = zone;
    el.dataset.landingSpot = landing;
    el.textContent = '⚓️';
    el.addEventListener('pointerdown', (e) => e.stopPropagation());
    el.addEventListener('pointerenter', (e) => e.stopPropagation());
    document.body.appendChild(el);
    landingMarkers.set(key, el);
    return el;
  }

  function registerLandingTargets(map) {
    landingTargets = map || {};
    for (const el of landingMarkers.values()) el.remove();
    landingMarkers.clear();
    for (const key of Object.keys(landingTargets)) ensureLandingMarker(key);
  }

  // 每帧把图标贴到各自上岸桩的上方；已经站在这个上岸点上时收起（不需要再"上岸"）。
  function updateLandingMarkers() {
    const diving = state.workerMode === 'DIVING';
    // DOM 图标没有深度测试：镜头拉近时，远处区块的锚会"浮"在前景的屋顶/甲板上，
    // 看起来就像图标在主界面上乱飘。按镜头距离收敛：拉近只看当前区块（+ 附近），
    // 拉到全图视角才把所有区块的锚显示出来；同时按距离缩放，远处的锚不再又大又抢眼。
    const camRange = camera.position.distanceTo(controls.target);
    const showRange = Math.max(14, Math.min(90, camRange * 0.78));
    for (const [key, el] of landingMarkers) {
      const entry = landingTargets[key];
      const group = entry?.group || entry;
      const { zone: zoneId, landing: landingId } = splitLandingKey(key);
      const zone = zones.get(zoneId);
      if (!group || !zone) { el.hidden = true; continue; }
      const alreadyHere = state.workerMode === 'IDLE_ASHORE'
        && state.currentZone === zoneId
        && (state.landingId || 'main') === landingId;
      const unlocked = zones.isUnlocked(zoneId, state);
      // 文案与可用性先写：图标的 title / aria-label 不随"当前是否隐藏"变化。
      el.disabled = !unlocked;
      const where = entry?.name && landingId !== 'main' ? entry.name : zone.name;
      const title = unlocked ? `在${where}上岸` : `${where}尚未开放`;
      if (el.title !== title) { el.title = title; el.setAttribute('aria-label', title); }
      group.getWorldPosition(landingAnchor);
      const nearTarget = controls.target.distanceTo(landingAnchor);
      const inRange = state.currentZone === zoneId || nearTarget <= showRange;
      landingProjected.set(landingAnchor.x, landingAnchor.y + 1.75, landingAnchor.z).project(camera);
      const onScreen = landingProjected.z > -1 && landingProjected.z < 1
        && Math.abs(landingProjected.x) < .99 && Math.abs(landingProjected.y) < .99;
      const show = !diving && !alreadyHere && onScreen && inRange;
      el.hidden = !show;
      if (!show) continue;
      const sx = (landingProjected.x * .5 + .5) * window.innerWidth;
      const sy = (-landingProjected.y * .5 + .5) * window.innerHeight;
      // 存一份屏幕坐标：图标本身 pointer-events:none（不挡其他点击），
      // 命中判定在 pickLandingAtScreen 里用这两个值做圆形容差。
      el._sx = sx;
      // translate(-50%,-100%)：底边贴锚点，命中按图标中心算。
      el._sy = sy - (el.offsetHeight || 34) / 2;
      el.style.left = `${sx.toFixed(1)}px`;
      el.style.top = `${sy.toFixed(1)}px`;
      // 镜头越远图标越小（20~32px），远处的锚不会盖过大半个画面。
      const dCam = camera.position.distanceTo(landingAnchor);
      const size = Math.round(Math.max(20, Math.min(32, 32 * (34 / Math.max(12, dCam)))));
      el.style.fontSize = `${size}px`;
      el.style.opacity = state.currentZone === zoneId ? '1' : '.82';
      // 停在这片水域的船上 → 这个锚就是"下船"，高亮一下。
      el.classList.toggle('is-current', state.currentZone === zoneId);
    }
  }

  // 海面漂浮的小木箱 / 木块 / 零件桶：属于物资，不挡船，必须开过去才收。
  const driftCrates = createDriftCrates({
    THREE,
    worldGroup,
    waterLevel: WATER_LEVEL,
    makeMaterial: (color) => (makePainterlyMat ? makePainterlyMat(color) : undefined),
    count: 10,
    pickupRadius: 1.7,
    // 物资只刷在区块周边一圈水道里，别撒到看不见的远海。
    spawnBounds: (() => {
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (const zone of zones.list) {
        for (const p of [zone.boatPark, zone.dockEdge, zone.landStand]) {
          minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
          minZ = Math.min(minZ, p.z); maxZ = Math.max(maxZ, p.z);
        }
      }
      const pad = 13;
      return { minX: minX - pad, maxX: maxX + pad, minZ: minZ - pad, maxZ: maxZ + pad };
    })(),
    isWaterPoint(x, z) {
      const grids = navGrids();
      const grid = grids[grids.length - 1];
      if (!isFree(grid, x, z)) return false;
      // 别刷在甲板上或紧贴建筑：离任何一个区块地块至少 2.2m。
      for (const zone of zones.list) {
        for (const r of zone.regions) {
          const dx = Math.max(r.minX - x, 0, x - r.maxX);
          const dz = Math.max(r.minZ - z, 0, z - r.maxZ);
          if (Math.hypot(dx, dz) < 2.2) return false;
        }
      }
      return true;
    },
    onCollect(reward, worldPos, label) {
      spawnResourceFlight(worldPos.clone().add(new THREE.Vector3(0, 0.9, 0)), reward);
      spawnFloatTip(worldPos.clone().add(new THREE.Vector3(0, 1.9, 0)), `🪵 ${label}`);
    }
  });

  // 海面鱼群：散在各处水面，划过去才亮出 🐟，捞一次少一条，捞完散群另处重聚。
  const fishSchools = createFishSchools({
    THREE,
    worldGroup,
    waterLevel: WATER_LEVEL,
    makeMaterial: (color) => (makePainterlyMat ? makePainterlyMat(color) : undefined),
    count: 7,
    random: Math.random,
    spawnBounds: (() => {
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (const zone of zones.list) {
        for (const p of [zone.boatPark, zone.dockEdge, zone.landStand]) {
          minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
          minZ = Math.min(minZ, p.z); maxZ = Math.max(maxZ, p.z);
        }
      }
      const pad = 12;
      return { minX: minX - pad, maxX: maxX + pad, minZ: minZ - pad, maxZ: maxZ + pad };
    })(),
    isWaterPoint(x, z) {
      const grids = navGrids();
      const grid = grids[grids.length - 1];
      if (!isFree(grid, x, z)) return false;
      for (const zone of zones.list) {
        for (const r of zone.regions) {
          const dx = Math.max(r.minX - x, 0, x - r.maxX);
          const dz = Math.max(r.minZ - z, 0, z - r.maxZ);
          if (Math.hypot(dx, dz) < 2.6) return false;
        }
      }
      return true;
    },
    onHarvest(reward, worldPos, depleted) {
      spawnResourceFlight(worldPos.clone().add(new THREE.Vector3(0, 0.7, 0)), reward);
      spawnFloatTip(worldPos.clone().add(new THREE.Vector3(0, 1.6, 0)), depleted ? '🐟 这群鱼捞完了' : '🐟 捞到一条鱼');
    }
  });

  // 漂浮物资到点结算（点选目标抵达 / 船停下时贴着）。
  function tryCollectCrate(crate, force = false) {
    if (!crate || !driftCrates.items.includes(crate)) return false;
    const boatPos = boatAnchorGroup.position;
    const walkerPos = explorerGroup.parent === scene ? explorerGroup.position : null;
    const near = Math.hypot(crate.group.position.x - boatPos.x, crate.group.position.z - boatPos.z) <= 2.4
      || (walkerPos && Math.hypot(crate.group.position.x - walkerPos.x, crate.group.position.z - walkerPos.z) <= 2.0);
    if (!force && !near) return false;
    const result = driftCrates.collect(crate, economy);
    if (result.ok) setWorkerStatus(`收下${result.label}`);
    else if (result.reason) spawnFloatTip(crate.group.position.clone().add(new THREE.Vector3(0, 1.6, 0)), result.reason);
    return result.ok;
  }

  // 划到某个漂浮物资旁边把它捡起来。
  function requestCrate(crate) {
    if (!crate) return false;
    if (workInProgress()) return false;
    const p = crate.group.position;
    state.activeJobSite = null;
    state.targetZone = state.currentZone;
    if (isBoatMode()) {
      state.pendingWorldTarget = { type: 'crate', crate };
      state.sailIntent = 'crate';
      state.sailTargetPos = new THREE.Vector3(p.x, WATER_LEVEL, p.z);
      state.sailCurve = buildSmoothSailCurve(state.currentZone, state.currentZone, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(2.0, state.sailCurve.getLength() / 3.6);
      state.workerMode = 'ROWING';
      state.camLockMode = 'boat';
      setWorkerStatus('正划向漂浮物资...');
      return true;
    }
    if (state.workerMode !== 'IDLE_ASHORE') return false;
    // 岸上：先走回岸边上船，再划过去。
    // 这里必须把 sailTargetPos 一起改掉 —— BOARDING 完成时是用它来规划航线的，
    // 留着上一次的值会"点了新目标却开去老地方"。
    state.pendingWorldTarget = { type: 'crate', crate };
    state.sailIntent = 'crate';
    state.sailTargetPos = new THREE.Vector3(p.x, WATER_LEVEL, p.z);
    const boardCrate = boardLanding(state.currentZone);
    if (boardCrate) state.walkTargetPos.copy(boardCrate.dockEdge);
    state.walkRegionId = getWalkRegionAt(state.walkTargetPos)?.id || null;
    state.workerMode = 'WALK_TO_BOAT';
    state.camLockMode = 'worker';
    setWorkerStatus('正走向岸边登船...');
    return true;
  }

  // 鱼群：船上靠得住就直接捞；离得远就先把船划过去，到了再点图标捞。
  function tryHarvestFish(school, force = false) {
    if (!school || !fishSchools.items.includes(school)) return false;
    const near = Math.hypot(school.base.x - boatAnchorGroup.position.x, school.base.z - boatAnchorGroup.position.z)
      <= fishSchools.harvestRadius;
    if (!force && !near) return false;
    const result = fishSchools.harvest(school, economy);
    if (result.ok) {
      syncCoinUI();
      setWorkerStatus(`捞到一条鱼（这群还剩 ${result.left} 条）`);
    } else if (result.reason) {
      spawnFloatTip(new THREE.Vector3(school.base.x, WATER_LEVEL + 1.4, school.base.z), result.reason);
    }
    return result.ok;
  }

  function requestFishSchool(school) {
    if (!school) return false;
    if (workInProgress()) return false;
    // 已经靠在鱼群边上：直接捞。
    if (isBoatMode()) {
      const gap = Math.hypot(school.base.x - boatAnchorGroup.position.x, school.base.z - boatAnchorGroup.position.z);
      if (gap <= fishSchools.harvestRadius) return tryHarvestFish(school, true);
    }
    // 停在鱼群「旁边」而不是正上方：船身压在鱼群上会把 🐟 图标和鱼群全遮住
    // （俯视时只看到一条船，看不出这里有鱼）。从当前船位方向退 2.1m 作为靠泊点。
    const away = new THREE.Vector3(
      boatAnchorGroup.position.x - school.base.x, 0,
      boatAnchorGroup.position.z - school.base.z
    );
    if (away.lengthSq() < 0.01) away.set(0, 0, 1);
    away.normalize().multiplyScalar(2.1);
    const spot = new THREE.Vector3(school.base.x + away.x, WATER_LEVEL, school.base.z + away.z);
    state.activeJobSite = null;
    state.targetZone = state.currentZone;
    if (isBoatMode()) {
      state.pendingWorldTarget = { type: 'fish', school };
      state.sailIntent = 'fish';
      state.sailTargetPos = spot;
      state.sailCurve = buildSmoothSailCurve(state.currentZone, state.currentZone, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(2.0, state.sailCurve.getLength() / 3.6);
      state.workerMode = 'ROWING';
      state.camLockMode = 'boat';
      setWorkerStatus('正划向鱼群...');
      return true;
    }
    if (state.workerMode !== 'IDLE_ASHORE') return false;
    state.pendingWorldTarget = { type: 'fish', school };
    state.sailIntent = 'fish';
    state.sailTargetPos = spot;
    const boardFish = boardLanding(state.currentZone);
    if (boardFish) state.walkTargetPos.copy(boardFish.dockEdge);
    state.walkRegionId = getWalkRegionAt(state.walkTargetPos)?.id || null;
    state.workerMode = 'WALK_TO_BOAT';
    state.camLockMode = 'worker';
    setWorkerStatus('正走向岸边登船...');
    return true;
  }

  // 人已经在这片水域的船上（停着）：就地停船、走上岸。
  // 注意船必须真的停在这个上岸点的泊位附近，否则先短程划过去 —— 绝不能
  // 让小人从半路的水面直接"飞"到岸上（那正是之前看起来跨区瞬移的原因）。
  function disembarkAtCurrentZone(zoneId = state.currentZone, landingId = state.landingId) {
    if (!isBoatMode()) return false;
    const landing = zones.landing(zoneId, landingId) || zones.landing(zoneId);
    if (!landing) return false;
    state.landingId = landing.id;
    const park = landing.boatPark;
    const gap = Math.hypot(boatAnchorGroup.position.x - park.x, boatAnchorGroup.position.z - park.z);
    if (gap > 2.6) {
      // 还没靠到这个上岸点的泊位：短程划过去，到站再下船。
      state.targetZone = zoneId;
      state.sailIntent = 'landing';
      state.sailTargetPos = new THREE.Vector3(park.x, WATER_LEVEL, park.z);
      state.sailCurve = buildSmoothSailCurve(zoneId, zoneId, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(2.0, state.sailCurve.getLength() / 3.6);
      state.workerMode = 'ROWING';
      state.camLockMode = 'boat';
      setWorkerStatus(`正划向${landing.name}上岸...`);
      return true;
    }
    unmountExplorerToWorld(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 0.5, 0)));
    state.jumpStartPos.copy(explorerGroup.position);
    state.jumpEndPos.copy(landing.dockEdge);
    state.transitionT = 0;
    state.sailIntent = 'landing';
    state.sailCurve = null;
    state.sailProgress = 0;
    state.sailTargetPos = null;
    state.pendingWorldTarget = null;
    state.workerMode = 'DISEMBARKING';
    state.camLockMode = zoneId;
    setWorkerStatus(`正在${landing.name}上岸...`);
    return true;
  }

  function requestLanding(zoneId, landingId = 'main') {
    const zone = zones.get(zoneId);
    if (!zone) return false;
    const landing = zones.landing(zoneId, landingId) || zones.landing(zoneId);
    if (!zones.isUnlocked(zoneId, state)) {
      spawnFloatTip(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 2, 0)), `⛵ 还不能前往${zone.name}`);
      return false;
    }
    if (state.workerMode === 'IDLE_ASHORE' && state.currentZone === zoneId && (state.landingId || 'main') === landing.id) {
      spawnFloatTip(explorerGroup.position.clone().add(new THREE.Vector3(0, 1.8, 0)), `已经在${landing.name || zone.name}岸上`);
      return false;
    }
    // 航行中：只有"本来就要去的那个上岸点"才排队上岸，别在半路把人扔下水。
    if (state.workerMode === 'ROWING') {
      if (zoneId === state.targetZone) {
        state.landingId = landing.id;
        state.sailIntent = 'landing';
        spawnFloatTip(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 2, 0)), '靠岸后自动上岸');
        return true;
      }
      spawnFloatTip(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 2, 0)), `正在前往${zones.label(state.targetZone)}，靠岸后再上岸`);
      return false;
    }
    // 人已经在这片水域里（停着）：直接停船下船，不绕一趟空航行。
    if (state.currentZone === zoneId && state.workerMode === 'BOAT_IDLE') return disembarkAtCurrentZone(zoneId, landing.id);
    if (state.workerMode !== 'IDLE_ASHORE') return false;
    // 只有这里成功走到「上船」才算数：先别改 landingId —— 以前先改后开船，
    // startSailBetweenZones 因为"同区块"直接返回 false，人会留在原地但 landingId 已经变了，
    // 之后所有取点（待机点/下船点）都指向另一块平台，看起来就是"人飞过去/区域不对"。
    const started = startSailBetweenZones(zoneId, null, landing);
    // 'landing' 与 'zone' 的到站处理一样（靠岸后走下船），单独标出来只为状态文案。
    if (started) state.sailIntent = 'landing';
    return started;
  }

  const elHcTitle = document.getElementById('hc-title');
  const elHcLvl = document.getElementById('hc-lvl');
  const elHcSummary = document.getElementById('hc-summary');

  function cancelHideTimer() {
    if (hideCardTimer) clearTimeout(hideCardTimer);
    hideCardTimer = null;
  }

  function hideHoverCard() {
    hoverCard.classList.remove('visible');
    hoverCard.setAttribute('aria-hidden', 'true');
    resourceOrbs.forEach(orb => orb.classList.remove('is-hot'));
  }

  function scheduleHideCard(delay = 90) {
    // Do not restart on every pointermove; the exit animation must start promptly.
    if (hideCardTimer) return;
    hideCardTimer = setTimeout(() => {
      hideHoverCard();
      hideCardTimer = null;
    }, delay);
  }

  function showHoverTarget(target) {
    cancelHideTimer();
    if (['actor', 'salvage', 'dock', 'economy'].includes(target.type)) {
      hideHoverCard();
      hoveredTarget = target;
      return;
    }
    const changed = !isSameTarget(hoveredTarget, target);
    const wasVisible = hoverCard.classList.contains('visible');
    hoveredTarget = target;
    renderHoverCardContent();
    positionHoverCardForTarget(target);
    hoverCard.setAttribute('aria-hidden', 'false');
    hoverCard.classList.add('visible');
    if (changed && wasVisible) hoverCard.querySelector('.hc-content').animate([
      { opacity: .35, transform: 'translateY(5px) scale(.95)' },
      { opacity: 1, transform: 'translateY(-1px) scale(1.025)', offset: .7 },
      { opacity: 1, transform: 'translateY(0) scale(1)' }
    ], { duration: 300, easing: 'cubic-bezier(.22,1,.36,1)' });
  }

  function positionHoverCardForTarget(target) {
    let worldAnchor;
    if (target.type === 'boat') {
      worldAnchor = boatAnchorGroup.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 2.2, 0));
    } else if (target.type === 'crate') {
      worldAnchor = target.crate.group.position.clone().add(new THREE.Vector3(0, 1.5, 0));
    } else if (target.type === 'fish') {
      worldAnchor = new THREE.Vector3(target.school.base.x, WATER_LEVEL + 1.5, target.school.base.z);
    } else if (target.type === 'landing') {
      const spot = zones.landing(target.zone, target.landing);
      worldAnchor = (spot ? spot.dockEdge.clone() : boatAnchorGroup.position.clone()).add(new THREE.Vector3(0, 2.4, 0));
    } else {
      worldAnchor = target.site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0));
    }
    const p = worldAnchor.project(camera);
    const visible = p.z > -1 && p.z < 1 && Math.abs(p.x) < .98 && Math.abs(p.y) < .98;
    hoverCard.classList.toggle('out-of-view', !visible);
    if (!visible) return;
    const x = (p.x * .5 + .5) * window.innerWidth;
    const y = (-p.y * .5 + .5) * window.innerHeight;
    const half = hoverCard.offsetWidth / 2;
    const shift = Math.max(12 + half - x, Math.min(0, window.innerWidth - 12 - half - x));
    hoverCard.style.setProperty('--edge-shift', `${shift}px`);
    // The card stays above its shared action hotspot, including near the top edge.
    hoverCard.style.left = `${x}px`;
    hoverCard.style.top = `${Math.max(hoverCard.offsetHeight + 12, y - 28)}px`;
  }

  function renderHoverCardContent() {
    if (!hoveredTarget || ['actor', 'salvage', 'dock', 'economy'].includes(hoveredTarget.type)) return;
    if (hoveredTarget.type === 'crate') {
      const spec = driftCrates.KINDS[hoveredTarget.crate.kind] || driftCrates.KINDS.crate;
      elHcTitle.textContent = spec.label;
      elHcLvl.textContent = '漂浮物资';
      const parts = Object.entries(spec.reward).map(([k, v]) => `${v} ${MATERIALS[k]?.name || k}`).join(' · ');
      elHcSummary.textContent = isBoatMode() ? `点击划过去拾取 · ${parts}` : `点击上船去拾取 · ${parts}`;
      hoverCard.classList.remove('can-upgrade');
      return;
    }
    if (hoveredTarget.type === 'fish') {
      const school = hoveredTarget.school;
      const near = Math.hypot(school.base.x - boatAnchorGroup.position.x, school.base.z - boatAnchorGroup.position.z)
        <= fishSchools.harvestRadius;
      elHcTitle.textContent = '海面鱼群';
      elHcLvl.textContent = `还有 ${school.fishCount} 条`;
      elHcSummary.textContent = near
        ? '点击捞一条鱼'
        : isBoatMode() ? '点击划过去 · 到旁边再捞' : '点击上船去鱼群';
      hoverCard.classList.remove('can-upgrade');
      return;
    }
    if (hoveredTarget.type === 'landing') {
      const zone = zones.get(hoveredTarget.zone);
      const spot = zones.landing(hoveredTarget.zone, hoveredTarget.landing);
      const where = spot && spot.id !== 'main' ? spot.name : zone?.name || hoveredTarget.zone;
      elHcTitle.textContent = `上岸 · ${where}`;
      const here = state.currentZone === hoveredTarget.zone
        && (state.landingId || 'main') === (spot?.id || 'main');
      elHcLvl.textContent = state.currentZone === hoveredTarget.zone ? '当前水域' : '可前往';
      elHcSummary.textContent = state.workerMode === 'IDLE_ASHORE' && here
        ? '已经在这里的岸上'
        : '点击自动航行靠岸并走上岸';
      hoverCard.classList.remove('can-upgrade');
      return;
    }
    if (hoveredTarget.type === 'boat') {
      elHcTitle.textContent = '小船与黑猫';
      elHcLvl.textContent = state.workerMode === 'IDLE_ASHORE' ? '停泊' : '航行中';
      elHcSummary.textContent = '点击小船 · 选择目的地';
      return;
    }
    const site = hoveredTarget.site;
    const { mode, available, missing, maxed, stage } = getSiteAction(site);
    elHcTitle.textContent = site.name.split(' · ').pop();
    elHcLvl.textContent = `Lv.${site.level}/${site.maxLevel}`;
    let summary;
    if (mode === 'harvest') summary = `收取 ${Math.floor(site.storedCoins)} 枚海贝`;
    else if (maxed) summary = '已满级';
    else if (state.workerMode !== 'IDLE_ASHORE') summary = state.activeJobSite === site
      ? state.workerMode === 'BUILDING' ? `培育中 · ${Math.round(state.jobProgress * 100)}%` : '正在前往培育'
      : '旅人忙碌中';
    else if (available) summary = `升级 · ${formatStageCost(stage)}`;
    else summary = `升级 · 还差 ${formatMissingCost(missing)}`;
    if (elHcSummary.textContent !== summary) elHcSummary.textContent = summary;
    hoverCard.classList.toggle('can-upgrade', mode === 'upgrade' && available);
  }

  function findHoverTargetFromIntersection(hitObj) {
    const economyTarget = economyView?.findTarget(hitObj);
    if (economyTarget) return economyTarget;
    const crate = driftCrates.findTarget(hitObj);
    if (crate) return { type: 'crate', crate };
    const school = fishSchools.findTarget(hitObj);
    if (school) return { type: 'fish', school };
    let curr = hitObj;
    while (curr) {
      if (curr === explorerGroup) {
        return { type: 'actor' };
      }
      if (curr === boatAnchorGroup || curr === boatMeshGroup) {
        return { type: 'boat' };
      }
      for (const [key, entry] of Object.entries(landingTargets)) {
        if (!entry) continue;
        if (curr === entry || curr === entry.group) {
          const { zone, landing } = splitLandingKey(key);
          return { type: 'landing', zone, landing };
        }
      }
      if (harborTargets.salvage && (curr === harborTargets.salvage || curr === harborTargets.salvage.poleGroup)) {
        return { type: 'salvage' };
      }
      if (harborTargets.dock && curr === harborTargets.dock) {
        return { type: 'dock' };
      }
      for (const s of buildSites) {
        if (s.hitRoots && s.hitRoots.includes(curr)) {
          return { type: 'site', site: s };
        }
      }
      curr = curr.parent;
    }
    return null;
  }

  function isSameTarget(a, b) {
    if (!a || !b) return false;
    if (a.type !== b.type) return false;
    if (a.type === 'site') return a.site.id === b.site.id;
    if (a.type === 'economy') return a.id === b.id;
    if (a.type === 'crate') return a.crate === b.crate;
    if (a.type === 'landing') return a.zone === b.zone && (a.landing || 'main') === (b.landing || 'main');
    return true;
  }

  // ⚓️ 图标本身不接管指针（否则会挡住下面小船、物资箱与地面的点击），
  // 所以命中判定在这里做：先看图标中心 20px 内，再看 3D 桩身 12px 内。
  // 这让"点图标"和"点桩子"都能上岸，而点击仍会穿透到 canvas 走统一路由。
  function pickLandingAtScreen(clientX, clientY) {
    let best = null;
    const consider = (key, sx, sy, radius) => {
      const entry = landingTargets[key];
      if (!entry) return;
      const el = landingMarkers.get(key);
      if (el?.disabled) return;
      const d = Math.hypot(sx - clientX, sy - clientY);
      if (d <= radius && (!best || d < best.d)) {
        const { zone, landing } = splitLandingKey(key);
        best = { d, target: { type: 'landing', zone, landing } };
      }
    };
    for (const [key, el] of landingMarkers) {
      if (el.hidden || !Number.isFinite(el._sx)) continue;
      consider(key, el._sx, el._sy, 20);
    }
    for (const [key, entry] of Object.entries(landingTargets)) {
      const g = entry?.group || entry;
      if (!g) continue;
      const p = g.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 0.9, 0)).project(camera);
      if (p.z < -1 || p.z > 1) continue;
      consider(key, (p.x * .5 + .5) * window.innerWidth, (-p.y * .5 + .5) * window.innerHeight, 12);
    }
    return best ? best.target : null;
  }

  function hitTargetAt(clientX, clientY) {
    const landingPick = pickLandingAtScreen(clientX, clientY);
    if (landingPick) return landingPick;
    // 采集/菜箱/设施的图标也是"只画图标"，命中同样按图标屏幕位置判定，
    // 否则图标浮在物件上方，鼠标点图标本体反而落空（之前热区对不上的原因）。
    const markerPick = economyView?.markerAt?.(clientX, clientY);
    if (markerPick) return markerPick;
    // 鱼群的 🐟 同理：图标浮在水面鱼群上方，按图标位置命中。
    const schoolPick = fishSchools.markerAt(clientX, clientY);
    if (schoolPick) return { type: 'fish', school: schoolPick };
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const roots = [boatMeshGroup, explorerGroup, driftCrates.root, fishSchools.root, ...Object.values(landingTargets).map(e => e?.group || e), harborTargets.salvage, harborTargets.dock, harborTargets.salvage?.poleGroup, ...(economyView?.roots || []), ...buildSites.flatMap(s => s.hitRoots || [])].filter(Boolean);
    const inFishRoot = (obj) => {
      for (let o = obj; o; o = o.parent) if (o === fishSchools.root) return true;
      return false;
    };
    const hit = raycaster.intersectObjects(roots, true).find(h => {
      // 鱼群贴着水面游，命中点会略低于水线，这一支要放行；其他物件仍然只认水面上方。
      if(h.point.y < WATER_LEVEL + .05 && !inFishRoot(h.object)) return false;
      for(let obj=h.object;obj;obj=obj.parent) if(!obj.visible) return false;
      return true;
    });
    if (!hit) return null;
    // 鱼群散在整片水域，默认俯视下经常在 115m 之外；鱼群放宽到接近相机远平面，
    // 否则"远处的鱼群点不到、也就没法划过去"。
    const reach = inFishRoot(hit.object) ? 178 : 115;
    return hit.distance < reach ? findHoverTargetFromIntersection(hit.object) : null;
  }

  // Both the building geometry and its action icon enter the same target state.
  window.addEventListener('pointermove', (e) => {
    if (state.workerMode === 'DIVING') return;
    if (e.buttons) return;
    if (e.target.closest?.('.resource-orb')) return;
    if (e.target !== renderer.domElement) {
      scheduleHideCard();
      return;
    }
    const target = hitTargetAt(e.clientX, e.clientY);
    renderer.domElement.style.cursor = target ? 'pointer' : 'default';
    // 图标是 canvas 上的纯 DOM 装饰（pointer-events:none），悬停反馈得由这里代劳。
    economyView?.setHot?.(target?.type === 'economy' ? target.id : null);
    if (target) showHoverTarget(target);
    else scheduleHideCard();
  });
  renderer.domElement.addEventListener('pointerleave', () => scheduleHideCard());

  let downPos = { x: 0, y: 0 };
  renderer.domElement.addEventListener('pointerdown', (e) => {
    downPos = { x: e.clientX, y: e.clientY };
  });

  function pointAtScreen(clientX, clientY, y) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const point = new THREE.Vector3();
    return raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -y), point) ? point : null;
  }

  function isBoatMode() {
    return state.workerMode === 'ROWING' || state.workerMode === 'BOAT_IDLE';
  }

  function isClearWaterPoint(point, clientX, clientY) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const distance = raycaster.ray.origin.distanceTo(point);
    const blocked = raycaster.intersectObjects(scene.children, true).some(hit => {
      if (hit.distance >= distance - .12 || hit.point.y < WATER_LEVEL - .05) return false;
      for (let obj = hit.object; obj; obj = obj.parent) {
        if (obj === waterPlane || obj === boatAnchorGroup || obj === boatMeshGroup || obj === explorerGroup) return false;
        // 漂浮物资和上岸桩是可穿过的水面标记，不该把水面点击挡掉。
        if (obj.userData?.noSailBlock) return false;
        if (!obj.visible) return false;
      }
      return true;
    });
    return !blocked;
  }

  function requestGroundMove(clientX, clientY) {
    if (state.workerMode !== 'IDLE_ASHORE') return false;
    const point = pointAtScreen(clientX, clientY, explorerGroup.getWorldPosition(new THREE.Vector3()).y);
    const region = point && getWalkRegionAt(point);
    if (!region || !isWalkSegmentClear(explorerGroup.position, point, region)) return false;
    state.walkRegionId = region.id;
    // 落点高度按真实模型取，配置里的 y 只在采样失败时兜底。
    const standY = regionStandHeight(region, point.x, point.z);
    state.walkTargetPos.set(point.x, standY === null ? region.y : standY, point.z);
    state.activeJobSite = null;
    state.workerMode = 'WALK_TO_POINT';
    state.camLockMode = 'worker';
    state.focusWorkerUntil = performance.now() + 1800;
    closeActionMenus();
    return true;
  }

  function queueSiteAction(site) {
    if (state.workerMode !== 'IDLE_ASHORE' && !isBoatMode()) return false;
    const action = getSiteAction(site);
    if (action.mode === 'upgrade' && !action.available) return false;
    if (action.mode === 'harvest' && Math.floor(site.storedCoins) <= 0) return false;

    if (action.mode === 'upgrade') {
      // 先扣除建设费用（海贝 + 基础材料），后续由角色抵达目标地块才开始施工。
      // 单次点击只结算一次：扣费后立刻把 activeJobSite 记下，重复调用会被上面的状态检查挡住。
      if (state.activeJobSite === site) return false;
      if (!economy.spend({ coins: action.stage.cost || 0, ...getStageMaterials(action.stage) })) return false;
      syncCoinUI();
      state.jobProgress = 0;
      state.activeJobSite = site;
      state.pendingWorldTarget = null;
    } else {
      state.activeJobSite = null;
      state.pendingWorldTarget = { type: 'harvest', site };
    }

    if (state.workerMode === 'IDLE_ASHORE' && state.currentZone === site.zone) {
      state.walkTargetPos.copy(site.buildStandPos);
      state.walkRegionId = getWalkRegionAt(site.buildStandPos)?.id || null;
      state.workerMode = 'WALK_TO_SITE';
      state.camLockMode = 'worker';
      return true;
    }

    if (isBoatMode()) {
      state.targetZone = site.zone;
      state.sailIntent = 'site';
      state.sailTargetPos = getZoneBoatPark(site.zone, 'main').clone();
      state.sailTargetPos.y = WATER_LEVEL;
      state.sailCurve = buildSmoothSailCurve(state.currentZone, site.zone, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(4.0, state.sailCurve.getLength() / 3.6);
      state.camLockMode = 'boat';
      state.workerMode = 'ROWING';
      return true;
    }

    state.targetZone = site.zone;
    // 岸上出发也要标清楚意图：BOARDING 完成后靠它决定是继续航行还是原地停船，
    // 漏了这一步船会开到目标水域却只停在船上、不上岸施工。
    state.sailIntent = 'site';
    state.sailTargetPos = getZoneBoatPark(site.zone, 'main').clone();
    state.sailTargetPos.y = WATER_LEVEL;
    state.landingId = 'main';
    const boardSite = boardLanding(state.currentZone);
    if (boardSite) state.walkTargetPos.copy(boardSite.dockEdge);
    state.workerMode = 'WALK_TO_BOAT';
    state.camLockMode = 'worker';
    return true;
  }

  renderer.domElement.addEventListener('pointerup', (e) => {
    const target = hitTargetAt(e.clientX, e.clientY);
    if (target?.type === 'economy') {
      hideHoverCard();
      economyView.handleTarget(target);
      return;
    }
    if (target?.type === 'boat') {
      hideHoverCard();
      if (state.workerMode === 'IDLE_ASHORE') {
        state.targetZone = state.currentZone;
        state.sailIntent = 'board';
        state.sailTargetPos = null;
        const boardHere = boardLanding(state.currentZone);
        if (boardHere) state.walkTargetPos.copy(boardHere.dockEdge);
        state.walkRegionId = getWalkRegionAt(state.walkTargetPos)?.id || null;
        state.workerMode = 'WALK_TO_BOAT';
        state.camLockMode = 'worker';
      } else if (isBoatMode()) {
        state.workerMode = 'BOAT_IDLE';
        state.sailCurve = null;
        state.sailTargetPos = null;
        state.sailIntent = 'free';
      }
      return;
    }
    if (target?.type === 'site') {
      hideHoverCard();
      activateSite(target.site);
      return;
    }
    if (target?.type === 'crate') {
      hideHoverCard();
      requestCrate(target.crate);
      return;
    }
    if (target?.type === 'landing') {
      hideHoverCard();
      requestLanding(target.zone, target.landing || 'main');
      return;
    }
    if (target?.type === 'fish') {
      hideHoverCard();
      requestFishSchool(target.school);
      return;
    }
    if (target?.type === 'salvage') {
      hideHoverCard();
      requestHarborAction('salvage');
      return;
    }
    if (target?.type === 'dock') {
      hideHoverCard();
      requestHarborAction('dock');
      return;
    }
    if (isBoatMode()) {
      const point = pointAtScreen(e.clientX, e.clientY, WATER_LEVEL);
      if (point && isClearWaterPoint(point, e.clientX, e.clientY)) {
        state.sailIntent = 'target';
        state.sailTargetPos = point.clone();
        state.buildingTarget = null;
        state.sailCurve = buildSmoothSailCurve(state.currentZone, state.currentZone, state.sailTargetPos);
        state.sailProgress = 0;
        state.sailDuration = Math.max(2.0, state.sailCurve.getLength() / 3.6);
        state.workerMode = 'ROWING';
        state.camLockMode = 'boat';
      }
      return;
    }

    if (!requestGroundMove(e.clientX, e.clientY)) {
      hideHoverCard();
      closeActionMenus();
    }
  });

  // ============================================================================
  // 10. 小人走上船 → 镜头拉高锁定跟随船 → 靠岸停船 → 走上岸浇水播种
  // ============================================================================
  // 上岸点 / 待机点 / 停泊位统一从注册表取，不再按区块写 if 链。
  // 船停在哪根桩旁边，人就从哪根桩上船。
  // 以前登船点固定用 state.landingId（那是「目的地」的桩），在绞盘打捞台上点去别区时，
  // 小人会朝主码头直线走过去 —— 中间全是水，看起来就是"人飞过海面"。
  function nearestLandingTo(zoneId, pos) {
    const list = zones.landingsOf(zoneId);
    if (!list.length) return null;
    if (!pos) return list[0];
    let best = list[0];
    let bestD = Infinity;
    for (const l of list) {
      const d = Math.hypot(l.dockEdge.x - pos.x, l.dockEdge.z - pos.z);
      if (d < bestD) { bestD = d; best = l; }
    }
    return best;
  }

  function boardLanding(zoneId = state.currentZone) {
    // 船的实际位置才是权威：人可能站在平台的另一侧，但只要船在这根桩旁边，
    // 就应该走回这根桩下船/上船，而不是横穿水面去另一块平台。
    return nearestLandingTo(zoneId, boatAnchorGroup.position)
      || nearestLandingTo(zoneId, explorerGroup.position);
  }

  // 一个区块可能有多个上岸点（主码头 + 独立平台），landingId 不传就取主码头。
  function getZoneShoreEdge(zoneId, landingId = state.landingId) {
    const landing = zones.landing(zoneId || state.currentZone, landingId);
    return landing ? landing.dockEdge : (homeZone.dockEdge);
  }

  function getZoneStandPos(zoneId, landingId = state.landingId) {
    const landing = zones.landing(zoneId || state.currentZone, landingId);
    return landing ? landing.landStand : (homeZone.landStand);
  }

  function getZoneBoatPark(zoneId, landingId = state.landingId) {
    const landing = zones.landing(zoneId || state.currentZone, landingId);
    return landing ? landing.boatPark : (homeZone.boatPark);
  }

  // —— 航行碰撞 ——
  // 船是 3.3m 长、1.5m 宽的真实实体，只靠「航迹避开包围盒」不够：
  // 规划层按船体半宽给障碍加净空后做栅格 A*（sail-nav.js），
  // 运行层再按真实船壳轮廓（15 排 × 每排 0.42m 密采样）做刚体推出，
  // 两层都要在：规划负责「别走进死路」，运行负责「别贴穿模型」。
  const BOAT_HULL_MARGIN = 0.14;       // 船壳再外扩一点，避免视觉上贴穿
  // 贴岸容差：给出 0.3m 的裕度，船靠泊/离泊原地转向时允许船壳贴住码头边缘一点点。
  // 完全按 0 容差算的话，船在窄水巷里永远靠不上岸（实测会卡在离停泊位 2.5m 处）。
  const BOAT_PENETRATION_ALLOW = 0.3;
  const BOAT_SCALE_X = 1.12;           // 船模型缩放（与 boatMeshGroup.scale 一致）
  const BOAT_SCALE_Z = 1.16;
  // 规划净空从宽到窄依次尝试：宽的先保证离墙远，窄巷再退让，全都不行才走直线。
  const NAV_CLEARANCES = [1.0, 0.74, 0.5];

  // 船壳真实轮廓的半宽（局部未缩放 z → 半宽），船头收窄、船尾略窄。
  function boatHullRadiusAt(lz) {
    if (lz > 2.85 || lz < -2.4) return -1;
    if (lz > 1.4) return 1.32 * (2.85 - lz) / 1.45;
    if (lz > -0.6) return 1.22 + 0.1 * ((lz + 0.6) / 2.0);
    return 0.95 + 0.27 * ((lz + 2.4) / 1.8);
  }

  // 高度带内所有会挡船实体的水平包围盒（未膨胀）。
  // 漂浮物资和上岸标记是「可穿过」的装饰，它们整棵子树带 noSailBlock，一律跳过。
  function collectSolidRects(loY, hiY) {
    const rects = [];
    scene.updateMatrixWorld(true);
    scene.traverse(object => {
      if (!object.isMesh || object.name === 'cartoon-water') return;
      for (let p = object; p; p = p.parent) {
        if (p === boatAnchorGroup || p === explorerGroup || p === waterPlane) return;
        if (!p.visible) return;
        if (p.userData?.noSailBlock) return;
      }
      const box = new THREE.Box3().setFromObject(object);
      if (!Number.isFinite(box.min.x) || box.isEmpty()) return;
      if (box.max.y < loY || box.min.y > hiY) return;
      rects.push({ minX: box.min.x, maxX: box.max.x, minZ: box.min.z, maxZ: box.max.z });
    });
    return rects;
  }

  // —— 规划层：水面栅格 A* ——
  // 旧的「碰到矩形就绕到它的四个角」只能一个一个躲，障碍密的时候会拐进死角或者干脆放弃绕行。
  // 现在把整片可航水域压成 0.5m 栅格，一次把所有障碍考虑进去，再把结果拉直。
  let navCache = null;

  function navBounds() {
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const zone of zones.list) {
      for (const spot of zone.landings) {
        for (const p of [spot.boatPark, spot.dockEdge, spot.landStand]) {
          minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
          minZ = Math.min(minZ, p.z); maxZ = Math.max(maxZ, p.z);
        }
      }
      for (const r of zone.regions) {
        minX = Math.min(minX, r.minX); maxX = Math.max(maxX, r.maxX);
        minZ = Math.min(minZ, r.minZ); maxZ = Math.max(maxZ, r.maxZ);
      }
    }
    const pad = 34;
    const bounds={ minX: minX - pad, maxX: maxX + pad, minZ: minZ - pad, maxZ: maxZ + pad };
    // Art-authored shorelines may extend beyond the original service islands.
    // Include their declared extent so the newly opened water remains navigable.
    worldGroup.traverse(node=>{
      const b=node.userData.sailBounds;if(!b)return;
      bounds.minX=Math.min(bounds.minX,b.minX);bounds.maxX=Math.max(bounds.maxX,b.maxX);
      bounds.minZ=Math.min(bounds.minZ,b.minZ);bounds.maxZ=Math.max(bounds.maxZ,b.maxZ);
    });
    return bounds;
  }

  function navGrids() {
    if (navCache) return navCache;
    const rects = collectSolidRects(WATER_LEVEL - .12, WATER_LEVEL + 2.8);
    const bounds = navBounds();
    navCache = NAV_CLEARANCES.map(clearance => createNavGrid({ rects, bounds, cell: 0.5, clearance }));
    return navCache;
  }

  // 供测试 / 场景重建后清缓存。
  function resetSailNav() {
    navCache = null;
  }

  function buildSailPath(start, end) {
    for (const grid of navGrids()) {
      const raw = findPath(grid, start, end);
      if (raw && raw.length >= 2) return smoothPath(grid, raw);
    }
    return null;
  }

  // 停泊位就在平台边上，原地把船头转过去会让船头/船尾扫过码头。
  // 所以出发时先沿当前船头方向驶出一小段，返港时沿停泊朝向倒推一小段再进泊 ——
  // 这一段「进出港引道」让转向发生在开阔水面，而不是贴着码头甩尾。
  function keepWaterPoint(x, z) {
    const grids = navGrids();
    return isFree(grids[grids.length - 1], x, z);
  }

  // 船壳放在 (x,z,yaw) 时是否不与任何实体相交。引道点必须过这一关 ——
  // 只看船心不够：船头比船心伸出去 3.2m，贴着码头的"空水点"照样会把船头插进平台。
  function hullClearAt(x, z, yaw) {
    const blockers = state.boatBlockers;
    if (!blockers || !blockers.length) return true;
    const cs = Math.cos(yaw);
    const sn = Math.sin(yaw);
    for (let lz = -2.4; lz <= 2.85; lz += 0.45) {
      const hw = boatHullRadiusAt(lz);
      if (hw < 0) continue;
      const radius = hw * BOAT_SCALE_X + BOAT_HULL_MARGIN;
      const dz = lz * BOAT_SCALE_Z;
      for (let u = -radius; u <= radius + 1e-6; u += 0.42) {
        const wx = x + u * cs + dz * sn;
        const wz = z - u * sn + dz * cs;
        for (const rect of blockers) {
          if (wx >= rect.minX && wx <= rect.maxX && wz >= rect.minZ && wz <= rect.maxZ) return false;
        }
      }
    }
    return true;
  }

  function withBerthStubs(_ignored, start, dest, startYaw, destYaw) {
    const pts = [];
    const push = (p) => {
      const last = pts[pts.length - 1];
      if (!last || Math.hypot(p.x - last.x, p.z - last.z) > 0.35) pts.push({ x: p.x, z: p.z });
    };
    const fwd = (yaw) => ({ x: Math.sin(yaw), z: Math.cos(yaw) });
    let from = start;
    let to = dest;
    let approach = null;

    // 出发：先沿当前船头方向驶出泊位，别在原地甩尾扫过码头。
    // 候选方向按「船头方向 ±30°/±60°」逐个试，取第一个船壳不碰东西、且落在水面上的。
    if (Number.isFinite(startYaw)) {
      for (const off of [0, 0.52, -0.52, 1.05, -1.05]) {
        const yaw = startYaw + off;
        const f = fwd(yaw);
        const depart = { x: start.x + f.x * 3.6, z: start.z + f.z * 3.6 };
        if (!keepWaterPoint(depart.x, depart.z)) continue;
        if (!hullClearAt(depart.x, depart.z, yaw)) continue;
        from = depart;
        break;
      }
    }
    // 进港：把「停泊位前方 N 米」当作终点，最后一段永远和停泊朝向同向。
    // N 从 4.2 逐步放到 7.2：船头比船心长 3.2m，太短的引道会让船头正好扫到码头角。
    if (Number.isFinite(destYaw)) {
      const f = fwd(destYaw);
      for (const dist of [4.2, 5.2, 6.2, 7.2]) {
        const a = { x: dest.x - f.x * dist, z: dest.z - f.z * dist };
        if (!keepWaterPoint(a.x, a.z)) continue;
        if (!hullClearAt(a.x, a.z, destYaw)) continue;
        approach = a;
        to = a;
        break;
      }
    }

    push(start);
    if (from !== start) push(from);
    const mid = buildSailPath(from, to) || [{ x: from.x, z: from.z }, { x: to.x, z: to.z }];
    for (const p of mid) push(p);
    if (approach) push(approach);
    push(dest);
    return pts;
  }

  // 圆 vs 矩形：返回把圆推出矩形所需的最小位移（已经在外侧且不重叠时返回 null）。
  function pushCircleOutOfRect(cx, cz, rect, radius) {
    const insideX = cx > rect.minX && cx < rect.maxX;
    const insideZ = cz > rect.minZ && cz < rect.maxZ;
    if (insideX && insideZ) {
      const dl = cx - rect.minX, dr = rect.maxX - cx, dn = cz - rect.minZ, df = rect.maxZ - cz;
      const m = Math.min(dl, dr, dn, df);
      if (m === dl) return { x: -(dl + radius), z: 0 };
      if (m === dr) return { x: dr + radius, z: 0 };
      if (m === dn) return { x: 0, z: -(dn + radius) };
      return { x: 0, z: df + radius };
    }
    const nx = Math.min(Math.max(cx, rect.minX), rect.maxX);
    const nz = Math.min(Math.max(cz, rect.minZ), rect.maxZ);
    const dx = cx - nx;
    const dz = cz - nz;
    const dist = Math.hypot(dx, dz);
    if (dist >= radius || dist < 1e-6) return null;
    const k = (radius - dist) / dist;
    return { x: dx * k, z: dz * k };
  }

  // 把船位修正到「船壳不与任何实体相交」的位置。
  // 用真实船壳轮廓采样而不是几个大圆：船尾比圆窄、船头收得更快，
  // 圆近似会漏掉船尾两角 —— 那正是靠岸时最常扫进平台的部位。
  function resolveBoatPosition(x, z, yaw) {
    const blockers = state.boatBlockers;
    if (!blockers || !blockers.length) return { x, z, pushed: 0 };
    // 只保留船体包围圆覆盖到的实体，避免每帧对着全图几百个矩形做检测。
    const near = [];
    for (const r of blockers) {
      if (r.maxX < x - 3.6 || r.minX > x + 3.6 || r.maxZ < z - 3.6 || r.minZ > z + 3.6) continue;
      near.push(r);
    }
    if (!near.length) return { x, z, pushed: 0 };

    let px = x, pz = z, pushed = 0;
    const cs = Math.cos(yaw), sn = Math.sin(yaw);
    // 刚体推出：每轮只处理「最深」的那一处穿透，并按 0.45m 步长位移。
    // 以前是每排船壳各自把同一个障碍推一遍 —— 贴着长平台时 15 排累加，
    // 一帧能把船推出 9m（实测整船从 z=-11 瞬移到 z=-21）。
    for (let iter = 0; iter < 12; iter++) {
      let deepest = null;
      for (let lz = -2.4; lz <= 2.85; lz += 0.35) {
        const hw = boatHullRadiusAt(lz);
        if (hw < 0) continue;
        const radius = Math.max(0.05, hw * BOAT_SCALE_X + BOAT_HULL_MARGIN - BOAT_PENETRATION_ALLOW);
        const dz = lz * BOAT_SCALE_Z;
        // 每一排沿船宽方向密采样：只取两端会漏掉细柱/箱角，船壳中段照样穿。
        for (let u = -radius; u <= radius + 1e-6; u += 0.42) {
          const wx = px + u * cs + dz * sn;
          const wz = pz - u * sn + dz * cs;
          for (const rect of near) {
            const push = pushCircleOutOfRect(wx, wz, rect, 0.05);
            if (!push) continue;
            const len = Math.hypot(push.x, push.z);
            if (!deepest || len > deepest.len) deepest = { x: push.x, z: push.z, len };
          }
        }
      }
      if (!deepest) break;
      const step = Math.min(1, 0.45 / deepest.len);
      px += deepest.x * step;
      pz += deepest.z * step;
      pushed += deepest.len * step;
    }
    return { x: px, z: pz, pushed };
  }

  function getBaseCameraOffset() {
    return state.camLockMode === 'boat' ? BOAT_FOLLOW_OFFSET : CAM_OFFSET;
  }

  function rememberUserZoom() {
    const base = getBaseCameraOffset();
    if (!base || !base.length()) return;
    const distance = camera.position.distanceTo(controls.target);
    cameraDistanceScale = THREE.MathUtils.clamp(distance / base.length(), 0.72, 2.25);
  }

  controls.addEventListener('end', rememberUserZoom);
  controls.addEventListener('start', () => {
    state.manualCamera = true;
    closeActionMenus();
    cancelHideTimer();
    hoveredTarget = null;
    hideHoverCard();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeActionMenus();
      hoveredTarget = null;
      hideHoverCard();
    }
  });

  // 右键拖动画面 = 用户接管镜头。接管后只保留 OrbitControls 自己的平移结果，
  // 不再被自动镜头拉回；从小人操作菜单选择聚焦或乘船后恢复跟随。
  renderer.domElement.addEventListener('contextmenu', (e) => e.preventDefault());
  renderer.domElement.addEventListener('pointerdown', (e) => {
    if (e.button === 2 && state.workerMode !== 'ROWING' && state.workerMode !== 'BOARDING') {
      state.manualCamera = true;
      closeActionMenus();
      hideHoverCard();
      hoveredTarget = null;
    }
  }, true);

  // 给出「从当前位置到目标点」的平滑航迹。先按宽净空找，再逐级退让；
  // 全都不通才退回直线（运行层的船壳推出会兜住，不至于穿模）。
  function buildSmoothSailCurve(fromZone, toZone, requestedTarget = null) {
    // 运行层只认「船壳高度带」内的实体。实测整船（含船上的人）世界包围盒顶到 2.35m，
    // 也就是水面 +1.23，所以上限取 +1.25：再高一点的东西船是完全从底下过去的，
    // 算进来会让推进求解在悬挑屋檐下无解、把船顶死在原地。
    state.boatBlockers = collectSolidRects(WATER_LEVEL + 0.08, WATER_LEVEL + 1.25);
    const startPt = boatAnchorGroup.position.clone();
    startPt.y = WATER_LEVEL;
    const destPark = (requestedTarget || getZoneBoatPark(toZone)).clone();
    destPark.y = WATER_LEVEL;

    // 只有"回区块停泊位"才需要对齐停泊朝向；点水面 / 点物资是就地停下，不需要。
    const parkRef = toZone ? getZoneBoatPark(toZone) : null;
    const alignsToPark = parkRef && Math.hypot(destPark.x - parkRef.x, destPark.z - parkRef.z) < 0.6;
    const poly = withBerthStubs(
      [],
      { x: startPt.x, z: startPt.z },
      { x: destPark.x, z: destPark.z },
      boatAnchorGroup.rotation.y,
      alignsToPark ? zones.get(toZone).boatYaw : NaN
    );

    const path = new THREE.CurvePath();
    let cursor = startPt.clone();
    let total = 0;
    for (const p of poly) {
      const next = new THREE.Vector3(p.x, WATER_LEVEL, p.z);
      const len = cursor.distanceTo(next);
      if (len < 0.05) continue;
      path.add(new THREE.LineCurve3(cursor, next));
      total += len;
      cursor = next;
    }
    if (total < 0.05) path.add(new THREE.LineCurve3(startPt, destPark));
    path.arcLengthDivisions = Math.max(64, poly.length * 16);
    state.sailPathPoints = poly.length;
    return path;
  }

  function updateTopButtonsHighlight(activeZone) {
    [btnCamOriginal, btnCamZone2, btnCamZone3].forEach((b) => {
      if (b) b.classList.remove('active');
    });
    if (activeZone === 'zone1' && btnCamOriginal) btnCamOriginal.classList.add('active');
    if (activeZone === 'zone2') btnCamZone2.classList.add('active');
    if (activeZone === 'zone3') btnCamZone3.classList.add('active');
  }

  // 去某个区块上岸。三种起点分别处理，别再一律写 WALK_TO_BOAT ——
  // 在船上时那样写会把角色状态改成"走向岸边"，人还在船上却开始走路（以前点目的地按钮会卡在这里）。
  function startSailBetweenZones(destZone, jobSiteAfterArrival = null, landing = null) {
    if (workInProgress() || !zones.get(destZone)) return false;
    if (!zones.isUnlocked(destZone, state)) return false;
    const target = landing || zones.landing(destZone, state.landingId);
    const sameZone = destZone === state.currentZone;
    // 同一区块里换一块平台（主码头 ↔ 绞盘打捞台）也要开船过去，不能因为"同区"直接拒绝。
    const sameLanding = sameZone && (state.landingId || 'main') === (target?.id || 'main');
    if (sameZone && sameLanding && !jobSiteAfterArrival && !isBoatMode()) return false;
    state.manualCamera = false;
    state.sailIntent = jobSiteAfterArrival ? 'site' : 'zone';
    updateTopButtonsHighlight(destZone);
    state.activeJobSite = jobSiteAfterArrival;
    state.pendingWorldTarget = null;
    state.targetZone = destZone;
    if (target) state.landingId = target.id;

    if (isBoatMode()) {
      // 已经在船上：直接规划航迹，不必再"走回岸边"。
      state.sailTargetPos = target.boatPark.clone();
      state.sailTargetPos.y = WATER_LEVEL;
      state.sailCurve = buildSmoothSailCurve(state.currentZone, destZone, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(2.4, state.sailCurve.getLength() / 3.6);
      state.workerMode = 'ROWING';
      state.camLockMode = 'boat';
      setWorkerStatus(`正划向${target.name || zones.label(destZone)}...`);
      return true;
    }

    // 上船点取「船停着的那根桩」，不是目的地的桩：从绞盘打捞台出发时
    // 走主码头要横穿海面，小人会像飞过去一样。
    const currentEdge = (boardLanding(state.currentZone) || target).dockEdge;
    // 岸上出发也要先把目标点定好：BOARDING 结束时直接拿它规划航线，
    // 不清掉上一次的值就会出现"点了 A 区却往 B 区开"。
    state.sailTargetPos = target.boatPark.clone();
    state.sailTargetPos.y = WATER_LEVEL;
    state.walkTargetPos.copy(currentEdge);
    state.workerMode = 'WALK_TO_BOAT';
    setWorkerStatus('正走向岸边登船...');
    return true;
  }

  function triggerBuildAtSite(site) {
    return queueSiteAction(site);
  }

  if (btnCamOriginal) {
    btnCamOriginal.addEventListener('click', () => {
      if (state.workerMode !== 'IDLE_ASHORE') return;
      updateTopButtonsHighlight('zone1');
      if (state.workerMode === 'IDLE_ASHORE' && state.currentZone !== 'zone1') {
        startSailBetweenZones('zone1', null);
      } else if (state.workerMode === 'IDLE_ASHORE') {
        state.manualCamera = false;
        state.camLockMode = 'zone1';
      }
    });
  }

  btnCamZone2.addEventListener('click', () => {
    if (state.workerMode !== 'IDLE_ASHORE') return;
    updateTopButtonsHighlight('zone2');
    if (state.workerMode === 'IDLE_ASHORE' && state.currentZone !== 'zone2') {
      startSailBetweenZones('zone2', null);
    } else if (state.workerMode === 'IDLE_ASHORE') {
      state.manualCamera = false;
      state.camLockMode = 'zone2';
    }
  });

  btnCamZone3.addEventListener('click', () => {
    if (state.workerMode !== 'IDLE_ASHORE') return;
    updateTopButtonsHighlight('zone3');
    if (state.workerMode === 'IDLE_ASHORE' && state.currentZone !== 'zone3') {
      startSailBetweenZones('zone3', null);
    } else if (state.workerMode === 'IDLE_ASHORE') {
      state.manualCamera = false;
      state.camLockMode = 'zone3';
    }
  });

  function mountExplorerIntoBoat() {
    boatMeshGroup.add(explorerGroup);
    explorerGroup.position.set(0, 0.52, -0.05);
    explorerGroup.rotation.set(0, Math.PI, 0);
    leftOarPivot.visible = true;
    rightOarPivot.visible = true;
  }

  function unmountExplorerToWorld(worldVec3) {
    scene.add(explorerGroup);
    explorerGroup.position.copy(worldVec3);
    explorerGroup.rotation.set(0, 0, 0);
    leftOarPivot.visible = false;
    rightOarPivot.visible = false;
  }

  // ============================================================================
  // 11. 主动画与状态机每帧更新（水底巨鲸、魔鬼鱼、排水管瀑布、信号灯、划船与种植）
  // ============================================================================
  let slowCoinTimer = 0;
  const WALK_SPEED = 1.15;
  const BOARDING_SPEED = 1.25;
  const DISEMBARK_SPEED = 1.3;
  const BUILD_SPEED = 0.16;
  const SAIL_SPEED_SCALE = 0.62;

  // 海面物资改为「看得见的漂浮物」，不再按里程随机掉落：
  // 走/划够一段就白送木料的做法会让"捡东西"这件事完全失去存在感。
  let cratesSpawned = false;
  function updateDriftCrates(elapsed, dt = 0) {
    // 等港口与遗迹都摆好之后再撒物资，否则会刷进建筑里。
    if (!cratesSpawned && elapsed > 1.2) {
      cratesSpawned = true;
      driftCrates.spawnAll();
      fishSchools.setCamera(camera);
      fishSchools.spawnAll();
    }
    fishSchools.update(dt, elapsed);
    const activeSchool = state.pendingWorldTarget?.type === 'fish' ? state.pendingWorldTarget.school : null;
    fishSchools.updateMarkers(state.workerMode === 'DIVING' ? null : boatAnchorGroup.position, activeSchool?.id ?? null);
    const onBoat = isBoatMode() || state.workerMode === 'BOARDING';
    const shouldPickup = onBoat
      ? (state.sailIntent === 'crate' || state.workerMode === 'BOAT_IDLE')
      : state.workerMode !== 'DIVING';
    return driftCrates.update(0, elapsed, {
      boatPos: boatAnchorGroup.position,
      walkerPos: explorerGroup.parent === scene ? explorerGroup.position : null,
      shouldPickup
    }, economy);
  }

  function updateGameplay(dt, elapsedTime) {
    const safeDt = Math.max(0, Math.min(Number.isFinite(dt) ? dt : 0, 0.1));
    economy.tick(safeDt);
    if (state.workerMode !== 'DIVING') updateDriftCrates(elapsedTime, safeDt);
    economyView?.update(safeDt, elapsedTime);

    // 绞盘冷却按真实时间回落；冷却结束只在岸上提醒一次，避免航行途中刷屏。
    if (state.salvageCooldown > 0) {
      const before = state.salvageCooldown;
      state.salvageCooldown = Math.max(0, state.salvageCooldown - safeDt);
      if (before > 0 && state.salvageCooldown <= 0 && state.workerMode === 'IDLE_ASHORE') {
        spawnFloatTip(new THREE.Vector3(-12, WATER_LEVEL + 4, 13), '绞盘已就绪');
      }
    }
    updateSalvageGauge(elapsedTime);

    // 挂机产出放缓：每 9 秒积累一次，攒满 10 份才亮收集标志，收一次大约要等一分半。
    slowCoinTimer += safeDt;
    if (slowCoinTimer >= 9.0) {
      slowCoinTimer -= 9.0;
      buildSites.forEach((s) => {
        if (s.coinsPerCycle > 0) {
          s.storedCoins = Math.min(10, s.storedCoins + s.coinsPerCycle);
        }
      });
      syncCoinUI();
      if (hoveredTarget && !['actor', 'salvage', 'dock', 'economy'].includes(hoveredTarget.type)) renderHoverCardContent();
    }

    // 2) 水下深海巨鲸巡游与摆尾动画（参考图3核心水底动态）
    const whaleAngle = elapsedTime * 0.16;
    const wx = -11.0 + Math.cos(whaleAngle) * 16.5;
    const wz = -7.5 + Math.sin(whaleAngle) * 14.5;
    const wy = -3.6 + Math.sin(elapsedTime * 0.55) * 0.65;
    const nextWhaleAngle = whaleAngle + 0.03;
    const nwx = -11.0 + Math.cos(nextWhaleAngle) * 16.5;
    const nwz = -7.5 + Math.sin(nextWhaleAngle) * 14.5;
    whaleGroup.position.set(wx, wy, wz);
    whaleGroup.lookAt(nwx, wy, nwz);
    whaleTailPivot1.rotation.y = Math.sin(elapsedTime * 2.1) * 0.28;
    whaleFlukePivot.rotation.x = Math.cos(elapsedTime * 2.1) * 0.35;

    // 3) 动态场景元素更新（瀑布、闪烁信号灯、魔鬼鱼、水母、大叶植物摇曳、黑猫呼吸）
    blackCatGroup.scale.y = 1.0 + Math.sin(elapsedTime * 3.2) * 0.04;
    updateResidentLife(elapsedTime, safeDt);

    dynamicAnimItems.forEach((item) => {
      if (item.type === 'sway_leaf') {
        item.obj.rotation.z = Math.sin(elapsedTime * item.speed + item.phase) * 0.08;
      } else if (item.type === 'jellyfish') {
        item.obj.position.y = item.baseY + Math.sin(elapsedTime * 2.4 + item.phase) * 0.12;
        const pulse = 1.0 + Math.sin(elapsedTime * 3.6 + item.phase) * 0.1;
        item.obj.scale.set(pulse, 2.0 - pulse, pulse);
      } else if (item.type === 'waterfall') {
        item.stream.scale.x = 0.92 + Math.sin(elapsedTime * 12.0) * 0.12;
        item.stream.scale.z = 0.92 + Math.cos(elapsedTime * 11.0) * 0.12;
        const spScale = 1.0 + ((elapsedTime * 1.8) % 0.8);
        item.splash.scale.set(spScale, spScale, 1);
        item.splash.material.opacity = Math.max(0.2, 0.95 - ((elapsedTime * 1.8) % 0.8));
      } else if (item.type === 'signal_blink') {
        const isGreen = Math.sin(elapsedTime * 3.5) > 0;
        item.obj.material.color.set(isGreen ? '#38ff7e' : '#ff4848');
      } else if (item.type === 'manta_glide') {
        const mAng = elapsedTime * 0.38;
        const mx = item.center.x + Math.cos(mAng) * item.rx;
        const mz = item.center.z + Math.sin(mAng) * item.rz;
        const nmx = item.center.x + Math.cos(mAng + 0.05) * item.rx;
        const nmz = item.center.z + Math.sin(mAng + 0.05) * item.rz;
        item.obj.position.set(mx, item.center.y + Math.sin(elapsedTime * 1.4) * 0.15, mz);
        item.obj.lookAt(nmx, item.obj.position.y, nmz);
        item.obj.rotation.z = Math.sin(elapsedTime * 2.6) * 0.12;
      } else if (item.type === 'bob_boat') {
        item.obj.position.y = item.baseY + Math.sin(elapsedTime * 1.9) * 0.06;
        item.obj.rotation.z = Math.sin(elapsedTime * 1.4) * 0.04;
      }
    });

    // 4) 小人登船 → 划船 → 靠岸停船 → 走上岸浇水播种状态机
    if (state.workerMode === 'IDLE_ASHORE') {
      window.__playerSailingActive = false;
      // 待机时也只认模型表面（配置里的 y 会随模型改动而过时）。
      settleFootY(explorerGroup, getWalkRegionAt(explorerGroup.position) || walkFootRegion());
      explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 2.2)) * 0.025;
      leftArmPivot.rotation.x = Math.sin(elapsedTime * 1.8) * 0.1;
      rightArmPivot.rotation.x = -Math.sin(elapsedTime * 1.8) * 0.1;
      leftLegPivot.rotation.x = 0;
      rightLegPivot.rotation.x = 0;
      buildProgressEl.style.display = 'none';
    } else if (state.workerMode === 'BOAT_IDLE') {
      window.__playerSailingActive = false;
      explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 2.2)) * 0.025;
      leftOarPivot.rotation.y = 0;
      rightOarPivot.rotation.y = 0;
      leftOarPivot.rotation.z = 0;
      rightOarPivot.rotation.z = 0;
      leftLegPivot.rotation.x = -1.1;
      rightLegPivot.rotation.x = -1.1;
      buildProgressEl.style.display = 'none';
    } else if (state.workerMode === 'WALK_TO_POINT') {
      window.__playerSailingActive = false;
      const dx = state.walkTargetPos.x - explorerGroup.position.x;
      const dz = state.walkTargetPos.z - explorerGroup.position.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.12) {
        const step = Math.min(dist, WALK_SPEED * safeDt);
        const next = explorerGroup.position.clone();
        next.x += (dx / dist) * step;
        next.z += (dz / dist) * step;
        const region = WALK_REGIONS.find(item => item.id === state.walkRegionId);
        if (region && isWalkSegmentClear(explorerGroup.position, next, region)) {
          explorerGroup.position.copy(next);
          settleFootThrottled(explorerGroup, region, safeDt);
        }
        explorerGroup.rotation.y = Math.atan2(dx, dz);
        leftLegPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.55;
        rightLegPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.55;
        leftArmPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.45;
        rightArmPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.45;
        explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 11)) * 0.05;
      } else {
        settleFootY(explorerGroup, WALK_REGIONS.find(item => item.id === state.walkRegionId) || walkFootRegion());
        state.workerMode = 'IDLE_ASHORE';
        state.camLockMode = state.currentZone;
      }
    } else if (state.workerMode === 'WALK_TO_BOAT') {
      window.__playerSailingActive = false;
      const dx = state.walkTargetPos.x - explorerGroup.position.x;
      const dz = state.walkTargetPos.z - explorerGroup.position.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.12) {
        const step = Math.min(dist, WALK_SPEED * safeDt);
        explorerGroup.position.x += (dx / dist) * step;
        explorerGroup.position.z += (dz / dist) * step;
        settleFootThrottled(explorerGroup, walkFootRegion(), safeDt);
        explorerGroup.rotation.y = Math.atan2(dx, dz);
        leftLegPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.55;
        rightLegPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.55;
        leftArmPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.45;
        rightArmPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.45;
        explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 11)) * 0.05;
      } else {
        state.workerMode = 'BOARDING';
        state.transitionT = 0;
        state.jumpStartPos.copy(explorerGroup.position);
        state.jumpEndPos.copy(boatAnchorGroup.position).add(new THREE.Vector3(0, 0.52, 0));
      }
      } else if (state.workerMode === 'BOARDING') {
        state.manualCamera = false;
        window.__playerSailingActive = true;
      state.transitionT = Math.min(1, state.transitionT + safeDt * BOARDING_SPEED);
      explorerGroup.position.lerpVectors(state.jumpStartPos, state.jumpEndPos, state.transitionT);
      explorerBodyPivot.position.y = Math.sin(state.transitionT * Math.PI) * 0.65;
      explorerGroup.lookAt(state.jumpEndPos.x, explorerGroup.position.y, state.jumpEndPos.z);

      if (state.transitionT >= 1) {
        explorerBodyPivot.position.y = 0;
        mountExplorerIntoBoat();
        state.camLockMode = 'boat';
        if (state.sailIntent === 'board' && state.targetZone === state.currentZone) {
          state.workerMode = 'BOAT_IDLE';
          state.sailIntent = 'free';
        } else {
          state.sailCurve = buildSmoothSailCurve(state.currentZone, state.targetZone, state.sailTargetPos);
          state.sailProgress = 0;
          const curveLen = state.sailCurve.getLength();
          state.sailDuration = Math.max(2.0, curveLen / 3.6);
          state.workerMode = 'ROWING';
        }
      }
    } else if (state.workerMode === 'ROWING') {
      window.__playerSailingActive = true;
      state.camLockMode = 'boat';

      const rowCycle = elapsedTime * 4.5;
      const rowSwing = Math.sin(rowCycle) * 0.55;
      const rowDip = Math.cos(rowCycle) * 0.18;
      leftOarPivot.rotation.y = rowSwing;
      leftOarPivot.rotation.z = rowDip;
      rightOarPivot.rotation.y = -rowSwing;
      rightOarPivot.rotation.z = -rowDip;

      explorerBodyPivot.rotation.x = Math.sin(rowCycle) * 0.22;
      leftArmPivot.rotation.x = -0.7 + Math.sin(rowCycle) * 0.45;
      rightArmPivot.rotation.x = -0.7 + Math.sin(rowCycle) * 0.45;
      leftLegPivot.rotation.x = -1.1;
      rightLegPivot.rotation.x = -1.1;

      const strokeBoost = 0.85 + Math.max(0, Math.sin(rowCycle)) * 0.45;
      state.sailProgress = Math.min(1, state.sailProgress + (safeDt / state.sailDuration) * strokeBoost * SAIL_SPEED_SCALE);

      if (state.sailCurve) {
        const pt = state.sailCurve.getPointAt(state.sailProgress);
        const tangent = state.sailCurve.getTangentAt(state.sailProgress);

        let desiredYaw = Math.atan2(tangent.x, tangent.z);
        // 靠岸最后 18% 逐渐转成「这次要去的那根桩」的停泊朝向，避免到位瞬间甩头。
        // 别用 zone.boatYaw —— 那只是主码头的朝向，独立平台（打捞台）的朝向不同。
        const destLanding = (state.sailIntent === 'zone' || state.sailIntent === 'site' || state.sailIntent === 'landing')
          ? zones.landing(state.targetZone, state.landingId)
          : null;
        if (destLanding && state.sailProgress > 0.82) {
          let parkDiff = destLanding.boatYaw - desiredYaw;
          while (parkDiff > Math.PI) parkDiff -= Math.PI * 2;
          while (parkDiff < -Math.PI) parkDiff += Math.PI * 2;
          desiredYaw += parkDiff * Math.min(1, (state.sailProgress - 0.82) / 0.18);
        }
        let diff = desiredYaw - boatAnchorGroup.rotation.y;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        boatAnchorGroup.rotation.y += diff * Math.min(1, safeDt * 7.5);

        // 船壳碰撞：曲线只是「想去哪」，最终落点必须过一遍实体推出，
        // 否则拐角处船头/船尾会直接扫进平台（观感就是完全没碰撞）。
        const fixed = resolveBoatPosition(pt.x, pt.z, boatAnchorGroup.rotation.y);
        // 修正量过大说明船已经被卡进大件里：这一帧留在原地，别瞬移出去。
        if (fixed.pushed <= 1.2) {
          boatAnchorGroup.position.x = fixed.x;
          boatAnchorGroup.position.z = fixed.z;
        }
      }

      if (state.sailProgress >= 1) {
        explorerBodyPivot.rotation.x = 0;
        // 到站分流：默认上岸；只有"停在水上办事"的意图（点水面/点物资/打捞台）才留在船上。
        const staysAfloat = state.sailIntent === 'target' || state.sailIntent === 'free' || state.sailIntent === 'crate' || state.sailIntent === 'fish';
        if (staysAfloat) {
          const pending = state.pendingWorldTarget;
          state.workerMode = 'BOAT_IDLE';
          state.sailCurve = null;
          state.sailTargetPos = null;
          state.pendingWorldTarget = null;
          state.sailIntent = 'free';
          if (pending?.type === 'salvage') performSalvage();
          if (pending?.type === 'dock') upgradeShip();
          if (pending?.type === 'crate') tryCollectCrate(pending.crate, true);
        } else {
          // landingId 可能来自上一个区块（比如上趟停在打捞台），到站先归一到本区块
          // 真实存在的上岸点，否则下船点/待机点会拿到其他区块的桩。
          const destLanding = zones.landing(state.targetZone, state.landingId)
            || zones.landing(state.targetZone, 'main');
          state.landingId = destLanding ? destLanding.id : 'main';
          // 靠泊吸附：曲线终点是泊位，但运行层每帧的船壳推出会把船挪开一点
          // （实测差 0.8m），角色下船点就会跟着漂。到这里直接贴回配置的泊位。
          const park = getZoneBoatPark(state.targetZone, state.landingId);
          const parkYaw = destLanding?.boatYaw;
          if (Number.isFinite(parkYaw)) boatAnchorGroup.rotation.y = parkYaw;
          const snapped = resolveBoatPosition(park.x, park.z, boatAnchorGroup.rotation.y);
          if (snapped.pushed <= 1.2) {
            boatAnchorGroup.position.x = snapped.x;
            boatAnchorGroup.position.z = snapped.z;
          }
          state.currentZone = state.targetZone;
          updateTopButtonsHighlight(state.currentZone);
          const shoreEdge = getZoneShoreEdge(state.currentZone);
          unmountExplorerToWorld(boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 0.5, 0)));
          state.jumpStartPos.copy(explorerGroup.position);
          state.jumpEndPos.copy(shoreEdge);
          state.transitionT = 0;
          state.workerMode = 'DISEMBARKING';
          state.camLockMode = state.currentZone;
        }
      }
    } else if (state.workerMode === 'DISEMBARKING') {
      window.__playerSailingActive = false;
      state.transitionT = Math.min(1, state.transitionT + safeDt * DISEMBARK_SPEED);
      explorerGroup.position.lerpVectors(state.jumpStartPos, state.jumpEndPos, state.transitionT);
      explorerBodyPivot.position.y = Math.sin(state.transitionT * Math.PI) * 0.55;
      explorerGroup.lookAt(state.jumpEndPos.x, explorerGroup.position.y, state.jumpEndPos.z);

      if (state.transitionT >= 1) {
        explorerBodyPivot.position.y = 0;
        settleFootY(explorerGroup, getWalkRegionAt(explorerGroup.position));
        const standTarget = state.activeJobSite
          ? state.activeJobSite.buildStandPos
          : getZoneStandPos(state.currentZone);
        state.walkTargetPos.copy(standTarget);
        state.walkRegionId = getWalkRegionAt(standTarget)?.id || null;
        state.workerMode = 'WALK_TO_SITE';
      }
    } else if (state.workerMode === 'WALK_TO_SITE') {
      window.__playerSailingActive = false;
      const dx = state.walkTargetPos.x - explorerGroup.position.x;
      const dz = state.walkTargetPos.z - explorerGroup.position.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.12) {
        const step = Math.min(dist, WALK_SPEED * safeDt);
        explorerGroup.position.x += (dx / dist) * step;
        explorerGroup.position.z += (dz / dist) * step;
        settleFootThrottled(explorerGroup, walkFootRegion(), safeDt);
        explorerGroup.rotation.y = Math.atan2(dx, dz);
        leftLegPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.55;
        rightLegPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.55;
        leftArmPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.45;
        rightArmPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.45;
      } else {
        leftLegPivot.rotation.x = 0;
        rightLegPivot.rotation.x = 0;
        // 到位再贴合一次：节流采样可能停在上一段台阶上。
        settleFootY(explorerGroup, walkFootRegion());
        if (state.activeJobSite) {
          state.workerMode = 'BUILDING';
          toolGroup.visible = true;
          setWorkerStatus(`正在浇水培育【${state.activeJobSite.name}】...`);
        } else {
          state.workerMode = 'IDLE_ASHORE';
          setWorkerStatus(zones.get(state.currentZone)?.status || '岸上待机');
        }
      }
    } else if (state.workerMode === 'BUILDING') {
      window.__playerSailingActive = false;
      const site = state.activeJobSite;
      if (!site) {
        state.workerMode = 'IDLE_ASHORE';
        return;
      }

      const stg = site.stages[site.level];
      state.jobProgress = Math.min(1, state.jobProgress + safeDt * BUILD_SPEED);
      if (stg && stg.applyVisual) {
        stg.applyVisual(state.jobProgress);
      }

      explorerGroup.lookAt(site.hoverAnchor.x, explorerGroup.position.y, site.hoverAnchor.z);
      rightArmPivot.rotation.x = -0.95 + Math.sin(elapsedTime * 11) * 0.55;
      leftArmPivot.rotation.x = -0.4 + Math.cos(elapsedTime * 7) * 0.25;
      explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 11)) * 0.04;


      if (state.jobProgress >= 1) {
        toolGroup.visible = false;
        buildProgressEl.style.display = 'none';
        site.level += 1;
        site.coinsPerCycle += stg.rateAdd;
        spawnFloatTip(site.hoverAnchor, `🌱 ${site.name} 培育完成！`);
        state.activeJobSite = null;
        state.workerMode = 'IDLE_ASHORE';
        setWorkerStatus('园圃培育完成，岸上待机');
        syncCoinUI();
        updateObjectiveUI();
        if (hoveredTarget && !['actor', 'salvage', 'dock', 'economy'].includes(hoveredTarget.type)) renderHoverCardContent();
      }
    }

    // 5) 相机锁定与跟随控制（保持固定画幅大小，进入船后锁定跟随船并适当往上拉高）
    // 用户右键拖动后进入 manualCamera，完全交给 OrbitControls 保持当前观察位置。
    if (!state.manualCamera) {
      let desiredTarget;
      let desiredCamPos;

      if (state.camLockMode === 'boat') {
        desiredTarget = boatAnchorGroup.position.clone().add(new THREE.Vector3(0, 1.0, 0));
        desiredCamPos = desiredTarget.clone().add(BOAT_FOLLOW_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      } else if (state.camLockMode === 'worker') {
        desiredTarget = explorerGroup.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 0.7, 0));
        desiredCamPos = desiredTarget.clone().add(WORKER_FOCUS_OFFSET.clone().multiplyScalar(cameraDistanceScale));
        if (performance.now() > state.focusWorkerUntil && state.workerMode === 'IDLE_ASHORE') {
          state.camLockMode = state.currentZone;
        }
      } else {
        // 区块取景由 zones.js 的 camera 决定，CAM_OFFSET 保持与 index.html 的拉远构图一致。
        const zoneCam = zones.get(state.camLockMode)?.camera || homeZone.camera;
        desiredTarget = zoneCam.clone();
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      }

      const baseCameraDistance = (state.camLockMode === 'boat' ? BOAT_FOLLOW_OFFSET : CAM_OFFSET).length();
      controls.minDistance = baseCameraDistance * 0.70;
      // The wider overview includes the first region's enclosing skyline and northeast bridge.
      // Camera far=600 and fog far=520 retain the back row at this distance.
      controls.maxDistance = baseCameraDistance * 2.25;
      isApplyingCameraLock = true;
      controls.target.lerp(desiredTarget, 0.06);
      camera.position.lerp(desiredCamPos, 0.06);
      isApplyingCameraLock = false;
    }
  }

  updateObjectiveUI();
  syncCoinUI();
  return {
    updateGameplay,
    performSalvage,
    upgradeShip,
    registerHarborTargets,
    registerLandingTargets,
    requestLanding,
    requestCrate,
    driftCrates,
    fishSchools,
    requestFishSchool,
    resetSailNav,
    requestHarborAction,
    salvage: salvageApi,
    economy,
    get economyView() { return economyView; },
    syncUI: syncCoinUI,
    travel: startSailBetweenZones,
    zones,
    // 调试/校验用：直接问「这个点能站在多高」和探针里收了几个 mesh。
    probe: {
      stand: (x, z, lo, hi) => sampleStandHeight(x, z, lo, hi),
      region: (id) => WALK_REGIONS.find((r) => r.id === id) || null,
      // 屏幕点最终会被派给谁（economy / site / boat / landing / fish …），null 表示落到地面。
      hit: (clientX, clientY) => hitTargetAt(clientX, clientY),
      meshCount: () => standProbeList().length,
      lastSettle: () => lastSettle,
      // 航行碰撞：给定船位/朝向返回推出后的位置与修正量（调试与回归用）。
      boatResolve: (x, z, yaw) => resolveBoatPosition(x, z, yaw),
      hullClear: (x, z, yaw) => hullClearAt(x, z, yaw),
      refreshBlockers: () => {
        state.boatBlockers = collectSolidRects(WATER_LEVEL + 0.08, WATER_LEVEL + 1.25);
        return state.boatBlockers.length;
      },
      boatBlockers: () => state.boatBlockers || [],
      // 寻路：给定起终点返回 A* 平滑后的航点（验证"这条路通不通"）。
      sailPath: (from, to) => buildSailPath(from, to),
      // 点击路由：给定屏幕坐标返回会命中的目标（回归用，避免只能靠肉眼点）。
      targetAt: (clientX, clientY) => {
        const t = hitTargetAt(clientX, clientY);
        return t ? { type: t.type, zone: t.zone || null, site: t.site?.id || null, crateId: t.crate?.id || null } : null;
      },
      navStats: () => navGrids().map(g => ({ clearance: g.clearance, cols: g.cols, rows: g.rows }))
    },
    art: { camera, zones, zone2Root, explorerGroup, boatAnchorGroup, stationPlatformGroup, trainCarGroup, stationCanopy, trackBedGroup, roadBedMesh, zone4Root, euroBuilding, houseBoatGroup, spout, zone3Root, planterTowerBody,
      planterSoil, rooftopSoilPatch, initialPlants, underwaterCityGroup, buildSites, state,
      resident: { group: resident.group, windowGlow, lantern: lanternGroup, homeSite },
      swimParts: { detail: characterDetail, explorerBodyPivot, leftArmPivot, rightArmPivot, leftLegPivot, rightLegPivot, toolGroup, hatBrim, hatCrown },
      crops: [z2CropStage1, z2CropStage2, z2CropStage3, z3CropStage1, z3CropStage2] },
    updateOverlays() {
      [btnCamOriginal, btnCamZone2, btnCamZone3].forEach(btn => { btn.disabled = state.workerMode !== 'IDLE_ASHORE'; });
      updateResourceOrbs();
      updateLandingMarkers();
      economyView?.updateOverlays();
      if (hoveredTarget && !['actor', 'salvage', 'dock', 'economy'].includes(hoveredTarget.type)) {
        renderHoverCardContent();
        positionHoverCardForTarget(hoveredTarget);
      }
      if (actorMenuOpen || destinationMenuOpen) positionActionMenus();
      const site = state.activeJobSite;
      if (site && state.workerMode === 'BUILDING') {
        const p = site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0)).project(camera);
        buildProgressEl.style.display = p.z > -1 && p.z < 1 && Math.abs(p.x) < 1 && Math.abs(p.y) < 1 ? 'inline-flex' : 'none';
        buildProgressEl.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
        buildProgressEl.style.top = `${(-p.y * .5 + .5) * window.innerHeight + 30}px`;
        document.getElementById('bp-fill').style.width = `${Math.round(state.jobProgress * 100)}%`;
      } else buildProgressEl.style.display = 'none';
      for (const [el, anchor] of floatTips) {
        const p = anchor.clone().project(camera);
        el.style.display = p.z > -1 && p.z < 1 ? '' : 'none';
        el.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
        el.style.top = `${(-p.y * .5 + .5) * window.innerHeight}px`;
      }
    }
  };
}
