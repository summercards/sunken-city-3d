/**
 * 《淹没之城：晴空水巷》第二区域（横滨沉没铁道道口）+ 四周环绕遗迹群 + 水上种植 + 水底巨鲸与建筑森林
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

export function initSunkenCityGameplay({
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
    btnCamOriginal.innerHTML = '<span>🏡 晴空水巷</span>';
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
    const refList = ['./reference.png', './ref_yokohama.png', './ref_overpass.png', './ref_underwater.png'];
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
    <button class="destination-btn" data-zone="zone1" title="晴空水巷" aria-label="晴空水巷">🏡</button>
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
    const visible = (!state.worldVisible || state.worldVisible(anchor)) && p.z > -1 && p.z < 1 && Math.abs(p.x) < 1 && Math.abs(p.y) < 1;
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
  function getSiteAction(site) {
    const hasResource = Math.floor(site.storedCoins) > 0;
    const maxed = site.level >= site.maxLevel;
    const stage = maxed ? null : site.stages[site.level];
    const available = !maxed && (state.workerMode === 'IDLE_ASHORE' || state.workerMode === 'BOAT_IDLE' || state.workerMode === 'ROWING') && state.coins >= stage.cost;
    return { mode: hasResource ? 'harvest' : 'upgrade', available, maxed, stage };
  }

  function harvestSite(site) {
    const orb = ensureResourceOrb(site);
    if (orb.classList.contains('collecting') || performance.now() < (orb.nextActionAt || 0)) return false;
    const gain = Math.floor(site.storedCoins);
    if (gain <= 0) return false;
    site.storedCoins -= gain;
    state.coins += gain;
    orb.nextActionAt = performance.now() + 700;
    orb.classList.add('collecting');
    spawnFloatTip(site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0)), `+${gain} 🐚`);
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
    if (action.available) {
      queueSiteAction(site);
      return true;
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
      const visible = (!state.worldVisible || state.worldVisible(site.hoverAnchor)) && p.z > -1 && p.z < 1 && Math.abs(p.x) < .98 && Math.abs(p.y) < .98;
      orb.classList.toggle('in-view', visible);
      orb.setAttribute('tabindex', visible ? '0' : '-1');
      orb.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
      orb.style.top = `${(-p.y * .5 + .5) * window.innerHeight}px`;
      const { mode, available, maxed } = getSiteAction(site);
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
      orb.setAttribute('aria-label', `${site.name}：${mode === 'harvest' ? `收取 ${Math.floor(site.storedCoins)} 枚海贝` : maxed ? '已满级' : available ? '升级' : '暂不可升级'}`);
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
  const ZONE2_CENTER = new THREE.Vector3(-28.0, 0, -18.0);
  const zone2Root = new THREE.Group();
  zone2Root.position.copy(ZONE2_CENTER);
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
  const ZONE3_CENTER = new THREE.Vector3(-15, 0, -6);
  const zone3Root = new THREE.Group();
  zone3Root.position.copy(ZONE3_CENTER);
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

  createSubmergedCar(-12.5, WATER_LEVEL + 0.15, 14.5, 0.42, '#8b68e8', '#d874aa');
  createLilyPadPatch(-15.5, 11.2, 9, 3.2);

  // 5.2 东北邻近区：【藤蔓断桥与晾衣生活船】（坐标 19.5, 0, -17.5 —— 从第一区域往右上看直接能感受到它在边上）
  const zone4Root = new THREE.Group();
  zone4Root.position.set(39.5, 0, -41.5);
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
  // 区域 1 停泊位（太阳能木屋橙色小码头前开阔水域）
  const ZONE1_BOAT_PARK = new THREE.Vector3(0.25, WATER_LEVEL, 5.45);
  const ZONE1_DOCK_EDGE = new THREE.Vector3(2.35, 2.02, 4.45);
  const ZONE1_DOCK_STAND = new THREE.Vector3(3.35, 2.02, 3.35);

  // 区域 2 停泊位：船湾落在轨道西南侧，靠岸后沿短栈桥走向站台与施工点
  const ZONE2_BOAT_PARK = new THREE.Vector3(-25.6, WATER_LEVEL, -15.0);
  const ZONE2_DOCK_EDGE = new THREE.Vector3(-28.6, WATER_LEVEL + 1.18, -17.1);
  const ZONE2_LAND_STAND = new THREE.Vector3(-30.7, WATER_LEVEL + 1.18, -18.3);

  // 区域 3 停泊位（西南邻近天台卫星锅种植园前开阔水域）
  const ZONE3_BOAT_PARK = new THREE.Vector3(-9, WATER_LEVEL, 1.5);
  const ZONE3_DOCK_EDGE = new THREE.Vector3(-10, 3.6, -2);
  const ZONE3_LAND_STAND = new THREE.Vector3(-13, 4.4, -5);
  // 远海街町先复用现有东北邻近区的生活船与断桥景观，作为 P0 的可见终点。
  const ZONE4_CENTER = new THREE.Vector3(39.5, 1.4, -41.5);
  const ZONE4_BOAT_PARK = new THREE.Vector3(33.8, WATER_LEVEL, -37.2);
  const ZONE4_DOCK_EDGE = new THREE.Vector3(36.8, WATER_LEVEL + 0.3, -39.4);
  const ZONE4_LAND_STAND = new THREE.Vector3(37.8, WATER_LEVEL + 0.3, -40.8);

  // 岸上可移动地块：只允许在同一块连续屋顶/码头内移动，水面和断开的楼块不是路面。
  const WALK_REGIONS = [
    {
      id: 'zone1_home_dock', zone: 'zone1', y: ZONE1_DOCK_STAND.y,
      contains(p) {
        return (p.x >= 0.0 && p.x <= 8.8 && p.z >= -5.8 && p.z <= 4.8) ||
          (p.x >= -2.5 && p.x <= 4.4 && p.z >= 4.0 && p.z <= 10.8) ||
          (p.x >= 0.7 && p.x <= 3.4 && p.z >= 3.8 && p.z <= 7.4);
      }
    },
    { id: 'zone3_farm', zone: 'zone3', y: 5.2, minX: -21.5, maxX: -8.5, minZ: -12.5, maxZ: 0.5 },
    { id: 'zone1_salvage', zone: 'zone1', y: WATER_LEVEL + .9, minX: -15.5, maxX: -8.5, minZ: 10.0, maxZ: 16.0 },
    { id: 'zone1_aqua', zone: 'zone1', y: WATER_LEVEL + 1.2, minX: 12.5, maxX: 19.5, minZ: 11.8, maxZ: 18.2 },
    { id: 'zone2_station', zone: 'zone2', y: WATER_LEVEL + 1.18, minX: -35.5, maxX: -20.0, minZ: -25.5, maxZ: -11.0 },
    { id: 'zone4_shore', zone: 'zone4', y: WATER_LEVEL + .3, minX: 31.5, maxX: 40.5, minZ: -43.5, maxZ: -34.5 }
  ];
  WALK_REGIONS.forEach(region => {
    if (!region.contains) region.contains = p => p.x >= region.minX && p.x <= region.maxX && p.z >= region.minZ && p.z <= region.maxZ;
  });

  function getWalkRegionAt(point) {
    return WALK_REGIONS.find(region => region.zone === state.currentZone && region.contains(point)) || null;
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

  boatAnchorGroup.position.copy(ZONE1_BOAT_PARK);
  boatAnchorGroup.rotation.y = -2.45;
  explorerGroup.position.copy(ZONE1_DOCK_STAND);
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
    shipLevel: 1,
    farSeaUnlocked: false,
    salvageRuns: 0,
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
    pendingWorldTarget: null,
    camLockMode: 'zone1',
    focusWorkerUntil: 0,
    manualCamera: false
  };

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
      hoverAnchor: new THREE.Vector3(-28.0, WATER_LEVEL + 4.2, -18.0),
      boatParkPos: ZONE2_BOAT_PARK,
      shoreEdgePos: ZONE2_DOCK_EDGE,
      buildStandPos: ZONE2_LAND_STAND,
      level: 0,
      maxLevel: 3,
      storedCoins: 0,
      coinsPerCycle: 0,
      stages: [
        {
          btnText: '🚣 划船去站台种植向日葵花圃 (20 🐚)',
          localBtnText: '🌱 在铁道站台播种向日葵花圃 (20 🐚)',
          desc: '小人划船前往横滨铁道道口，登岸在混凝土高架站台上开辟木框花床并种下芭蕉与向日葵。',
          cost: 20,
          rateAdd: 2,
          applyVisual(progress) {
            z2CropStage1.visible = true;
            z2CropStage1.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去电车顶培育空中花园 (40 🐚)',
          localBtnText: '🌿 在复古电车顶种植藤蔓花海 (40 🐚)',
          desc: '在半淹没的蓝白复古电车车顶培育翠绿热带植物丛与鲜花，让沉没铁道焕发生机。',
          cost: 40,
          rateAdd: 3,
          applyVisual(progress) {
            z2CropStage2.visible = true;
            z2CropStage2.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去水道培育发光睡莲与水母 (65 🐚)',
          localBtnText: '🪷 培育铁道发光睡莲与水母群 (65 🐚)',
          desc: '在枕木水道间播撒发光睡莲，吸引透明发光水母环绕道口游弋。',
          cost: 65,
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
      hoverAnchor: new THREE.Vector3(-19.5, WATER_LEVEL + 4.5, 13.5),
      boatParkPos: ZONE3_BOAT_PARK,
      shoreEdgePos: ZONE3_DOCK_EDGE,
      buildStandPos: ZONE3_LAND_STAND,
      level: 0,
      maxLevel: 2,
      storedCoins: 0,
      coinsPerCycle: 0,
      stages: [
        {
          btnText: '🚣 划船去天台花池种植龟背竹 (25 🐚)',
          localBtnText: '🌱 浇水种植大叶龟背竹与花丛 (25 🐚)',
          desc: '划向圆弧农场，在圆弧屋顶的木框土槽里种满大叶龟背竹。',
          cost: 25,
          rateAdd: 3,
          applyVisual(progress) {
            z3CropStage1.visible = true;
            z3CropStage1.scale.setScalar(Math.max(0.05, progress));
          }
        },
        {
          btnText: '🚣 划船去扩建天台巨叶芭蕉林 (50 🐚)',
          localBtnText: '🌴 培育丰茂芭蕉林与翡翠花果 (50 🐚)',
          desc: '悉心浇灌整座屋顶花坛，让翠绿宽大的热带芭蕉叶与花朵铺满天台。',
          cost: 50,
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
      name: '晴空水巷 · 太阳能木屋花圃',
      // 只命中太阳能木屋本体；船仍由独立的 boatMeshGroup 负责交互。
      hitRoots: [houseGroupRef || boatMeshGroup],
      hoverAnchor: new THREE.Vector3(4.3, WATER_LEVEL + 4.8, -0.4),
      boatParkPos: ZONE1_BOAT_PARK,
      shoreEdgePos: ZONE1_DOCK_EDGE,
      buildStandPos: ZONE1_DOCK_STAND,
      level: 1,
      maxLevel: 2,
      storedCoins: 0,
      coinsPerCycle: 1,
      stages: [
        {},
        {
          btnText: '🚣 划船回木屋种花与挂灯 (20 🐚)',
          localBtnText: '🌱 在木屋码头种花并点亮暖灯 (20 🐚)',
          desc: '在起始木屋码头种植水上盆栽花丛，并点亮暖黄航标灯笼。',
          cost: 20,
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
    elCoinRate.textContent = '';
  }

  function setWorkerStatus(text) {
    elWorkerStatus.textContent = text;
  }

  function awardResource(resource, amount, anchor, label) {
    state[resource] += amount;
    syncCoinUI();
    spawnFloatTip(anchor, `+${amount} ${label}`);
  }

  function updateObjectiveUI() {
    const farSea = destinationWheel.querySelector('[data-zone="zone4"]');
    farSea.disabled = !state.farSeaUnlocked;
    farSea.setAttribute('aria-disabled', String(!state.farSeaUnlocked));
  }

  function performSalvage() {
    if (state.workerMode !== 'IDLE_ASHORE' || state.salvageRuns >= 3) return false;
    state.salvageRuns += 1;
    const anchor = new THREE.Vector3(-12, WATER_LEVEL + 4, 13);
    awardResource('wood', 3, anchor, '🪵');
    awardResource('parts', 2, anchor.clone().add(new THREE.Vector3(0, .5, 0)), '⚙');
    syncCoinUI();
    return true;
  }

  function upgradeShip() {
    if (state.farSeaUnlocked || state.workerMode !== 'IDLE_ASHORE' || state.wood < 6 || state.parts < 4) return false;
    state.wood -= 6;
    state.parts -= 4;
    state.shipLevel = 2;
    state.farSeaUnlocked = true;
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
  }

  function requestHarborAction(kind) {
    if (kind === 'salvage' && state.workerMode === 'IDLE_ASHORE' && state.currentZone === 'zone1') return performSalvage();
    if (kind === 'dock' && (state.workerMode === 'IDLE_ASHORE' || state.workerMode === 'BOAT_IDLE')) return upgradeShip();
    if (!isBoatMode()) return false;
    const target = kind === 'salvage' ? new THREE.Vector3(-12, WATER_LEVEL, 13) : new THREE.Vector3(.3, WATER_LEVEL, 9);
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
    if (target.type === 'actor' || target.type === 'salvage' || target.type === 'dock') {
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
    const worldAnchor = target.type === 'boat'
      ? boatAnchorGroup.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 2.2, 0))
      : target.site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0));
    const inGrid = !state.worldVisible || state.worldVisible(worldAnchor);
    const p = worldAnchor.project(camera);
    const visible = p.z > -1 && p.z < 1 && Math.abs(p.x) < .98 && Math.abs(p.y) < .98;
    hoverCard.classList.toggle('out-of-view', !visible || !inGrid);
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
    if (!hoveredTarget || hoveredTarget.type === 'actor' || hoveredTarget.type === 'salvage' || hoveredTarget.type === 'dock') return;
    if (hoveredTarget.type === 'boat') {
      elHcTitle.textContent = '小船与黑猫';
      elHcLvl.textContent = state.workerMode === 'IDLE_ASHORE' ? '停泊' : '航行中';
      elHcSummary.textContent = '点击小船 · 选择目的地';
      return;
    }
    const site = hoveredTarget.site;
    const { mode, available, maxed, stage } = getSiteAction(site);
    elHcTitle.textContent = site.name.split(' · ').pop();
    elHcLvl.textContent = `Lv.${site.level}/${site.maxLevel}`;
    let summary;
    if (mode === 'harvest') summary = `收取 ${Math.floor(site.storedCoins)} 枚海贝`;
    else if (maxed) summary = '已满级';
    else if (state.workerMode !== 'IDLE_ASHORE') summary = state.activeJobSite === site
      ? state.workerMode === 'BUILDING' ? `培育中 · ${Math.round(state.jobProgress * 100)}%` : '正在前往培育'
      : '旅人忙碌中';
    else summary = available ? `升级 · ${stage.cost} 枚海贝` : `升级 · 还差 ${Math.ceil(stage.cost - state.coins)} 枚海贝`;
    if (elHcSummary.textContent !== summary) elHcSummary.textContent = summary;
    hoverCard.classList.toggle('can-upgrade', mode === 'upgrade' && available);
  }

  function findHoverTargetFromIntersection(hitObj) {
    let curr = hitObj;
    while (curr) {
      if (curr === explorerGroup) {
        return { type: 'actor' };
      }
      if (curr === boatAnchorGroup || curr === boatMeshGroup) {
        return { type: 'boat' };
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
    return true;
  }

  function hitTargetAt(clientX, clientY) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const roots = [boatMeshGroup, explorerGroup, harborTargets.salvage, harborTargets.dock, harborTargets.salvage?.poleGroup, ...buildSites.flatMap(s => s.hitRoots || [])].filter(Boolean);
    const hit = raycaster.intersectObjects(roots, true).find(h => {
      if(h.point.y < WATER_LEVEL + .05 || state.worldVisible && !state.worldVisible(h.point)) return false;
      for(let obj=h.object;obj;obj=obj.parent) if(!obj.visible) return false;
      return true;
    });
    return hit && hit.distance < 115 ? findHoverTargetFromIntersection(hit.object) : null;
  }

  // Both the building geometry and its action icon enter the same target state.
  window.addEventListener('pointermove', (e) => {
    if (e.buttons) return;
    if (e.target.closest?.('.resource-orb')) return;
    if (e.target !== renderer.domElement) {
      scheduleHideCard();
      return;
    }
    const target = hitTargetAt(e.clientX, e.clientY);
    renderer.domElement.style.cursor = target ? 'pointer' : 'default';
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
    state.walkTargetPos.set(point.x, region.y, point.z);
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
      // 先扣除建设费用，后续由角色抵达目标地块才开始施工。
      state.coins -= action.stage.cost;
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
      state.sailTargetPos = site.shoreEdgePos.clone();
      state.sailTargetPos.y = WATER_LEVEL;
      state.sailCurve = buildSmoothSailCurve(state.currentZone, site.zone, state.sailTargetPos);
      state.sailProgress = 0;
      state.sailDuration = Math.max(4.0, state.sailCurve.getLength() / 3.6);
      state.camLockMode = 'boat';
      state.workerMode = 'ROWING';
      return true;
    }

    state.targetZone = site.zone;
    state.walkTargetPos.copy(getZoneShoreEdge(state.currentZone));
    state.workerMode = 'WALK_TO_BOAT';
    state.camLockMode = 'worker';
    return true;
  }

  renderer.domElement.addEventListener('pointerup', (e) => {
    if (e.button !== 0 || Math.hypot(e.clientX - downPos.x, e.clientY - downPos.y) > 6) return;
    const target = hitTargetAt(e.clientX, e.clientY);
    if (target?.type === 'boat') {
      hideHoverCard();
      if (state.workerMode === 'IDLE_ASHORE') {
        state.targetZone = state.currentZone;
        state.sailIntent = 'board';
        state.sailTargetPos = null;
        state.walkTargetPos.copy(getZoneShoreEdge(state.currentZone));
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
      queueSiteAction(target.site);
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
      if (point && (!state.worldVisible || state.worldVisible(point)) && isClearWaterPoint(point, e.clientX, e.clientY)) {
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
  function getZoneShoreEdge(zoneId) {
    if (zoneId === 'zone5') return new THREE.Vector3(13, 1.8, 14);
    if (zoneId === 'zone2') return ZONE2_DOCK_EDGE;
    if (zoneId === 'zone3') return ZONE3_DOCK_EDGE;
    if (zoneId === 'zone4') return ZONE4_DOCK_EDGE;
    return ZONE1_DOCK_EDGE;
  }

  function getZoneStandPos(zoneId) {
    if (zoneId === 'zone5') return new THREE.Vector3(15, 1.8, 15);
    if (zoneId === 'zone2') return ZONE2_LAND_STAND;
    if (zoneId === 'zone3') return ZONE3_LAND_STAND;
    if (zoneId === 'zone4') return ZONE4_LAND_STAND;
    return ZONE1_DOCK_STAND;
  }

  function getZoneBoatPark(zoneId) {
    if (zoneId === 'zone5') return new THREE.Vector3(11, WATER_LEVEL, 12);
    if (zoneId === 'zone2') return ZONE2_BOAT_PARK;
    if (zoneId === 'zone3') return ZONE3_BOAT_PARK;
    if (zoneId === 'zone4') return ZONE4_BOAT_PARK;
    return ZONE1_BOAT_PARK;
  }

  // 航线只在水面移动，并在每次点击时绕开会露出水面的建筑/平台包围盒。
  function getSailObstacleRects(start, end) {
    const rects = [];
    const startBox = { x: start.x, z: start.z };
    const endBox = { x: end.x, z: end.z };
    const contains = (r, p, pad = 0) => p.x >= r.minX - pad && p.x <= r.maxX + pad && p.z >= r.minZ - pad && p.z <= r.maxZ + pad;
    scene.updateMatrixWorld(true);
    scene.traverse(object => {
      if (!object.isMesh || !object.visible || object === waterPlane || object === boatMeshGroup || object === explorerGroup) return;
      let parent = object.parent;
      while (parent) {
        if (parent === boatAnchorGroup || parent === explorerGroup || parent === waterPlane) return;
        parent = parent.parent;
      }
      const box = new THREE.Box3().setFromObject(object);
      if (!Number.isFinite(box.min.x) || box.max.y < WATER_LEVEL - .12 || box.min.y > WATER_LEVEL + 2.8) return;
      const rect = { minX: box.min.x - 1.1, maxX: box.max.x + 1.1, minZ: box.min.z - 1.1, maxZ: box.max.z + 1.1 };
      if (contains(rect, startBox, .05) || contains(rect, endBox, .05)) return;
      if (rect.maxX - rect.minX < .5 || rect.maxZ - rect.minZ < .5) return;
      if (!rects.some(existing => Math.abs(existing.minX - rect.minX) < .18 && Math.abs(existing.minZ - rect.minZ) < .18 && Math.abs(existing.maxX - rect.maxX) < .18 && Math.abs(existing.maxZ - rect.maxZ) < .18)) rects.push(rect);
    });
    return rects;
  }

  function segmentHitsRect(a, b, r) {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const p = (x, z) => {
      const qx = Math.abs(dx) < 1e-6 ? Infinity : (x - a.x) / dx;
      const qz = Math.abs(dz) < 1e-6 ? Infinity : (z - a.z) / dz;
      return Math.max(qx, qz);
    };
    if (a.x >= r.minX && a.x <= r.maxX && a.z >= r.minZ && a.z <= r.maxZ) return true;
    if (b.x >= r.minX && b.x <= r.maxX && b.z >= r.minZ && b.z <= r.maxZ) return true;
    const edges = [[r.minX, r.minZ, r.maxX, r.minZ], [r.maxX, r.minZ, r.maxX, r.maxZ], [r.maxX, r.maxZ, r.minX, r.maxZ], [r.minX, r.maxZ, r.minX, r.minZ]];
    for (const [x1, z1, x2, z2] of edges) {
      const den = (x1 - x2) * (a.z - b.z) - (z1 - z2) * (a.x - b.x);
      if (Math.abs(den) < 1e-6) continue;
      const u = ((x1 - x2) * (z1 - a.z) - (z1 - z2) * (x1 - a.x)) / den;
      const v = ((a.x - b.x) * (z1 - a.z) - (a.z - b.z) * (x1 - a.x)) / den;
      if (u >= 0 && u <= 1 && v >= 0 && v <= 1) return true;
    }
    return false;
  }

  function buildSafeSailPoints(start, end) {
    const rects = getSailObstacleRects(start, end);
    const points = [start.clone()];
    let cursor = start.clone();
    for (let pass = 0; pass < 8; pass++) {
      const obstacle = rects.find(r => segmentHitsRect(cursor, end, r));
      if (!obstacle) break;
      const corners = [
        new THREE.Vector3(obstacle.minX, WATER_LEVEL, obstacle.minZ),
        new THREE.Vector3(obstacle.maxX, WATER_LEVEL, obstacle.minZ),
        new THREE.Vector3(obstacle.maxX, WATER_LEVEL, obstacle.maxZ),
        new THREE.Vector3(obstacle.minX, WATER_LEVEL, obstacle.maxZ)
      ];
      const candidates = corners.filter(c => !rects.some(r => segmentHitsRect(cursor, c, r)));
      if (!candidates.length) break;
      candidates.sort((a, b) => (a.distanceTo(cursor) + a.distanceTo(end)) - (b.distanceTo(cursor) + b.distanceTo(end)));
      const detour = candidates[0];
      points.push(detour.clone());
      cursor = detour;
      rects.splice(rects.indexOf(obstacle), 1);
    }
    points.push(end.clone());
    return points;
  }

  function getBaseCameraOffset() {
    return state.camLockMode === 'boat' ? BOAT_FOLLOW_OFFSET : CAM_OFFSET;
  }

  function rememberUserZoom() {
    const base = getBaseCameraOffset();
    if (!base || !base.length()) return;
    const distance = camera.position.distanceTo(controls.target);
    cameraDistanceScale = THREE.MathUtils.clamp(distance / base.length(), 0.72, 1.85);
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

  function buildSmoothSailCurve(fromZone, toZone, requestedTarget = null) {
    const makeRoute = (points) => {
      const safePoints = [];
      for (let i = 0; i < points.length - 1; i++) {
        const segment = buildSafeSailPoints(points[i], points[i + 1]);
        if (i > 0) segment.shift();
        safePoints.push(...segment);
      }
      const path = new THREE.CurvePath();
      for (let i = 0; i < safePoints.length - 1; i++) {
        path.add(new THREE.LineCurve3(safePoints[i], safePoints[i + 1]));
      }
      path.arcLengthDivisions = Math.max(64, safePoints.length * 32);
      return path;
    };
    const startPt = boatAnchorGroup.position.clone();
    const destPark = (requestedTarget || getZoneBoatPark(toZone)).clone();
    destPark.y = WATER_LEVEL;

    if (toZone === 'zone3' || fromZone === 'zone3' || toZone === 'zone5' || fromZone === 'zone5') {
      return makeRoute([startPt, new THREE.Vector3(-5, WATER_LEVEL, 7), destPark]);
    }
    if (fromZone === 'zone1' && toZone === 'zone2') {
      // 从木屋码头出发 → 穿过中央深水峡谷 → 沿铁道西南侧平行接近船湾
      return makeRoute([
        startPt,
        new THREE.Vector3(-0.6, WATER_LEVEL, 1.8),
        new THREE.Vector3(-2.2, WATER_LEVEL, -5.8),
        new THREE.Vector3(-8.8, WATER_LEVEL, -12.0),
        new THREE.Vector3(-16.8, WATER_LEVEL, -14.8),
        new THREE.Vector3(-22.2, WATER_LEVEL, -15.2),
        destPark
      ]);
    }
    if (fromZone === 'zone2' && toZone === 'zone1') {
      return makeRoute([
        startPt,
        new THREE.Vector3(-22.2, WATER_LEVEL, -15.2),
        new THREE.Vector3(-16.8, WATER_LEVEL, -14.8),
        new THREE.Vector3(-8.8, WATER_LEVEL, -12.0),
        new THREE.Vector3(-2.2, WATER_LEVEL, -5.8),
        new THREE.Vector3(-0.6, WATER_LEVEL, 1.8),
        destPark
      ]);
    }
    if (fromZone === 'zone1' && toZone === 'zone3') {
      // 从木屋码头向西南绕过前景电杆水域直达天台种植园
      return makeRoute([
        startPt,
        new THREE.Vector3(-1.2, WATER_LEVEL, 7.8),
        new THREE.Vector3(-5.5, WATER_LEVEL, 10.4),
        new THREE.Vector3(-10.2, WATER_LEVEL, 11.9),
        destPark
      ]);
    }
    if (fromZone === 'zone3' && toZone === 'zone1') {
      return makeRoute([
        startPt,
        new THREE.Vector3(-10.2, WATER_LEVEL, 11.9),
        new THREE.Vector3(-5.5, WATER_LEVEL, 10.4),
        new THREE.Vector3(-1.2, WATER_LEVEL, 7.8),
        destPark
      ]);
    }
    if (fromZone === 'zone3' && toZone === 'zone2') {
      return makeRoute([
        startPt,
        new THREE.Vector3(-18.5, WATER_LEVEL, 4.0),
        new THREE.Vector3(-22.5, WATER_LEVEL, -2.2),
        new THREE.Vector3(-25.2, WATER_LEVEL, -8.8),
        destPark
      ]);
    }
    if (fromZone === 'zone2' && toZone === 'zone3') {
      return makeRoute([
        startPt,
        new THREE.Vector3(-25.2, WATER_LEVEL, -8.8),
        new THREE.Vector3(-22.5, WATER_LEVEL, -2.2),
        new THREE.Vector3(-18.5, WATER_LEVEL, 4.0),
        destPark
      ]);
    }
    if (toZone === 'zone4' || fromZone === 'zone4') {
      const direction = toZone === 'zone4' ? 1 : -1;
      return makeRoute([
        startPt,
        new THREE.Vector3(3.5 * direction, WATER_LEVEL, -5.0),
        new THREE.Vector3(10.0 * direction, WATER_LEVEL, -11.0),
        new THREE.Vector3(14.0 * direction, WATER_LEVEL, -13.0),
        destPark
      ]);
    }
    return makeRoute([startPt, destPark]);
  }

  function updateTopButtonsHighlight(activeZone) {
    [btnCamOriginal, btnCamZone2, btnCamZone3].forEach((b) => {
      if (b) b.classList.remove('active');
    });
    if (activeZone === 'zone1' && btnCamOriginal) btnCamOriginal.classList.add('active');
    if (activeZone === 'zone2') btnCamZone2.classList.add('active');
    if (activeZone === 'zone3') btnCamZone3.classList.add('active');
  }

  function startSailBetweenZones(destZone, jobSiteAfterArrival = null) {
    if (state.workerMode !== 'IDLE_ASHORE') return;
    state.manualCamera = false;
    state.sailIntent = jobSiteAfterArrival ? 'site' : 'zone';
    updateTopButtonsHighlight(destZone);
    state.activeJobSite = jobSiteAfterArrival;
    state.targetZone = destZone;

    const currentEdge = getZoneShoreEdge(state.currentZone);
    state.walkTargetPos.copy(currentEdge);
    state.workerMode = 'WALK_TO_BOAT';
    setWorkerStatus('正走向岸边登船...');
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

  function updateGameplay(dt, elapsedTime) {
    const safeDt = Math.min(dt, 0.1);

    // 每 6 秒按建筑产出等级积累海贝，每处最多存储 10 枚。
    slowCoinTimer += safeDt;
    if (slowCoinTimer >= 6.0) {
      slowCoinTimer -= 6.0;
      buildSites.forEach((s) => {
        if (s.coinsPerCycle > 0) {
          s.storedCoins = Math.min(10, s.storedCoins + s.coinsPerCycle);
        }
      });
      syncCoinUI();
      if (hoveredTarget && !['actor', 'salvage', 'dock'].includes(hoveredTarget.type)) renderHoverCardContent();
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
      explorerGroup.position.y = getWalkRegionAt(explorerGroup.position)?.y || explorerGroup.position.y;
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
        if (region && isWalkSegmentClear(explorerGroup.position, next, region)) explorerGroup.position.copy(next);
        explorerGroup.rotation.y = Math.atan2(dx, dz);
        leftLegPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.55;
        rightLegPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.55;
        leftArmPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.45;
        rightArmPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.45;
        explorerBodyPivot.position.y = Math.abs(Math.sin(elapsedTime * 11)) * 0.05;
      } else {
        explorerGroup.position.y = WALK_REGIONS.find(item => item.id === state.walkRegionId)?.y || explorerGroup.position.y;
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
        boatAnchorGroup.position.x = pt.x;
        boatAnchorGroup.position.z = pt.z;

        const desiredYaw = Math.atan2(tangent.x, tangent.z);
        let diff = desiredYaw - boatAnchorGroup.rotation.y;
        while (diff > Math.PI) diff -= Math.PI * 2;
        while (diff < -Math.PI) diff += Math.PI * 2;
        boatAnchorGroup.rotation.y += diff * Math.min(1, safeDt * 7.5);
      }

      if (state.sailProgress >= 1) {
        explorerBodyPivot.rotation.x = 0;
        if (state.sailIntent === 'target' || state.sailIntent === 'free') {
          const pending = state.pendingWorldTarget;
          state.workerMode = 'BOAT_IDLE';
          state.sailCurve = null;
          state.sailTargetPos = null;
          state.pendingWorldTarget = null;
          state.sailIntent = 'free';
          if (pending?.type === 'salvage') performSalvage();
          if (pending?.type === 'dock') upgradeShip();
        } else {
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
        explorerGroup.rotation.y = Math.atan2(dx, dz);
        leftLegPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.55;
        rightLegPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.55;
        leftArmPivot.rotation.x = -Math.sin(elapsedTime * 11) * 0.45;
        rightArmPivot.rotation.x = Math.sin(elapsedTime * 11) * 0.45;
      } else {
        leftLegPivot.rotation.x = 0;
        rightLegPivot.rotation.x = 0;
        if (state.activeJobSite) {
          state.workerMode = 'BUILDING';
          toolGroup.visible = true;
          setWorkerStatus(`正在浇水培育【${state.activeJobSite.name}】...`);
        } else {
          state.workerMode = 'IDLE_ASHORE';
          const zName =
            state.currentZone === 'zone2'
              ? '横滨铁道站台待机'
              : state.currentZone === 'zone3'
              ? '天台种植园待机'
              : '木屋码头待机';
          setWorkerStatus(zName);
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
        if (hoveredTarget && !['actor', 'salvage', 'dock'].includes(hoveredTarget.type)) renderHoverCardContent();
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
      } else if (state.camLockMode === 'zone2') {
        desiredTarget = ZONE2_CENTER.clone().add(new THREE.Vector3(0.0, 1.2, 0.0));
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      } else if (state.camLockMode === 'zone3') {
        desiredTarget = ZONE3_CENTER.clone().add(new THREE.Vector3(0.0, 1.6, 0.0));
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      } else if (state.camLockMode === 'zone5') {
        desiredTarget = new THREE.Vector3(16, 1.5, 15);
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      } else if (state.camLockMode === 'zone4') {
        desiredTarget = ZONE4_CENTER.clone();
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      } else {
        desiredTarget = new THREE.Vector3(0.45, 1.75, -0.65);
        // 与 index.html 的拉远构图保持一致，同时保留用户滚轮选择的距离。
        desiredCamPos = desiredTarget.clone().add(CAM_OFFSET.clone().multiplyScalar(cameraDistanceScale));
      }

      const baseCameraDistance = (state.camLockMode === 'boat' ? BOAT_FOLLOW_OFFSET : CAM_OFFSET).length();
      controls.minDistance = baseCameraDistance * 0.70;
      controls.maxDistance = baseCameraDistance * 1.78;
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
    requestHarborAction,
    art: { camera, zone2Root, explorerGroup, boatAnchorGroup, stationPlatformGroup, trainCarGroup, stationCanopy, trackBedGroup, roadBedMesh, zone4Root, euroBuilding, houseBoatGroup, spout, zone3Root, planterTowerBody,
      planterSoil, rooftopSoilPatch, initialPlants, underwaterCityGroup, buildSites, state,
      resident: { group: resident.group, windowGlow, lantern: lanternGroup, homeSite },
      crops: [z2CropStage1, z2CropStage2, z2CropStage3, z3CropStage1, z3CropStage2] },
    updateOverlays() {
      [btnCamOriginal, btnCamZone2, btnCamZone3].forEach(btn => { btn.disabled = state.workerMode !== 'IDLE_ASHORE'; });
      updateResourceOrbs();
      if (hoveredTarget && !['actor', 'salvage', 'dock'].includes(hoveredTarget.type)) {
        renderHoverCardContent();
        positionHoverCardForTarget(hoveredTarget);
      }
      if (actorMenuOpen || destinationMenuOpen) positionActionMenus();
      const site = state.activeJobSite;
      if (site && state.workerMode === 'BUILDING') {
        const p = site.hoverAnchor.clone().add(new THREE.Vector3(0, .6, 0)).project(camera);
        buildProgressEl.style.display = (!state.worldVisible || state.worldVisible(site.hoverAnchor)) && p.z > -1 && p.z < 1 && Math.abs(p.x) < 1 && Math.abs(p.y) < 1 ? 'inline-flex' : 'none';
        buildProgressEl.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
        buildProgressEl.style.top = `${(-p.y * .5 + .5) * window.innerHeight + 30}px`;
        document.getElementById('bp-fill').style.width = `${Math.round(state.jobProgress * 100)}%`;
      } else buildProgressEl.style.display = 'none';
      for (const [el, anchor] of floatTips) {
        const p = anchor.clone().project(camera);
        el.style.display = (!state.worldVisible || state.worldVisible(anchor)) && p.z > -1 && p.z < 1 ? '' : 'none';
        el.style.left = `${(p.x * .5 + .5) * window.innerWidth}px`;
        el.style.top = `${(-p.y * .5 + .5) * window.innerHeight}px`;
      }
    }
  };
}
