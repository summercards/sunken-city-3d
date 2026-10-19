// Core islands have breathing room; distant districts remain available when sailing.
export function arrangeHarbor({ THREE:T, worldGroup, gameplay, sceneArt, leftBuildingGroup, poleGroup, makePainterlyMat:mat, WATER_LEVEL:water }) {
  const {buildSites,state,zone3Root}=gameplay.art;
  // 区块坐标统一来自 zones.js：搬动区块时这里跟着走，不再各自写一份。
  const zones=gameplay.zones;
  const zone3=zones.get('zone3');
  leftBuildingGroup.position.set(zone3.origin.x,zone3.origin.y,zone3.origin.z);
  zone3Root.visible=false;
  // Carry the animated windmill onto the farm rather than leaving it on the retired roof.
  leftBuildingGroup.add(sceneArt.rotor);sceneArt.rotor.position.set(3.8,6.6,0);
  const farm=buildSites.find(s=>s.id==='rooftop_planter');
  farm.hitRoots=[leftBuildingGroup];farm.hoverAnchor.copy(zone3.hoverAnchor);
  // Remove redundant underwater filler from the navigable channels.
  worldGroup.children.filter(g=>g.userData.legacyTower).forEach(g=>{
    if(g.position.x<0) g.visible=false;
  });
  const box=(p,x,y,z,w,h,d,color)=>{const m=new T.Mesh(new T.BoxGeometry(w,h,d),mat(color));m.position.set(x,y,z);p.add(m);return m;};
  function island(name,x,z,w,d){const g=new T.Group();g.name=name;g.position.set(x,0,z);worldGroup.add(g);
    box(g,0,.9,0,w,.5,d,'#a9c6b5');
    for(const sx of [-1,1])for(const sz of [-1,1])box(g,sx*(w/2-.4),-3,sz*(d/2-.4),.45,8,.45,'#639fa1');return g;}
  const salvageSpot=zones.harborPoint('salvage');
  const dockSpot=zones.harborPoint('dock');
  const salvage=island('C · 绞盘打捞台',salvageSpot.x,salvageSpot.z,6.5,5.5);
  for(let i=0;i<10;i++)box(salvage,-2.9+i*.64,1.24,0,.58,.18,5.3,'#c49c6e');
  poleGroup.position.set(salvageSpot.x,-4.5,salvageSpot.z);poleGroup.scale.setScalar(.72);
  box(salvage,1.5,1.7,-1.2,1.4,.9,1.2,'#d8b879');
  box(salvage,1.5,2.2,-1.2,1.5,.12,1.3,'#ede0b6');
  const dock=island('D · 交易码头',dockSpot.x,dockSpot.z,5,4);
  for(let i=0;i<8;i++)box(dock,-2.15+i*.62,1.3,0,.55,.16,4,'#d5a56d');
  for(const x of [-2,2])box(dock,x,1.7,1.5,.25,1.1,.25,'#806951');
  // Short gangway connects the home shore to the dedicated dock.
  const bridge=box(worldGroup,1.8,1.55,6.1,1.5,.2,3.2,'#d6b887');bridge.rotation.y=-.4;
  box(leftBuildingGroup,3.8,5.1,0,.16,3,.16,'#8d9577');
  const aquaZone=zones.get('zone5');
  const aquaSpot=aquaZone.site;
  const aqua=island('E · 浅水养殖台',aquaSpot.x,aquaSpot.z,6.5,5.5);
  const plants=[];
  for(const x of [-1.6,1.6])for(const z of [-1.3,1.3]){
    box(aqua,x,1.23,z,2.7,.25,2.1,'#6ba69b');box(aqua,x,1.38,z,2.25,.08,1.65,'#4b989e');
    for(let i=0;i<3;i++){const p=new T.Mesh(new T.SphereGeometry(.35,6,4),mat('#a9c86e'));p.position.set(x-.6+i*.6,1.5,z);p.scale.set(1,.24,.7);p.visible=false;aqua.add(p);plants.push(p);}
  }
  const aquaSite={id:'shallow_aquaculture',zone:'zone5',name:'浅水养殖台',hitRoots:[aqua],hoverAnchor:aquaZone.hoverAnchor.clone(),boatParkPos:zones.get('zone5').boatPark.clone(),shoreEdgePos:zones.get('zone5').dockEdge.clone(),buildStandPos:zones.get('zone5').landStand.clone(),level:0,maxLevel:1,storedCoins:0,coinsPerCycle:0,stages:[{cost:35,materials:{wood:3,parts:2,pearl:1},requires:{boat2:2},rateAdd:2,desc:'用远海珍珠培育浅水池，消耗3木料、2旧零件与1珍珠。船只2级后开放修建。',applyVisual(p){plants.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(p-.35-i*.025)*3));m.visible=a>0;m.scale.set(a,.24*a,.7*a);});}}]};
  buildSites.push(aquaSite);
  // Harbor targets are consumed by the single click router in gameplay.js.
  salvage.poleGroup = poleGroup;
  gameplay.registerHarborTargets({ salvage, dock });
  // 每个上岸点立一根「上岸桩」：点它 = 自动航行靠岸 + 角色走上岸。
  // 桩子贴着平台边缘外侧 0.55m（以前放在水域中间，看起来跟平台毫无关系，还会随镜头漂移），
  // 整组带 noSailBlock —— 能被点到，但绝不挡船。
  const landings = {};
  for (const zone of zones.list) {
    for (const spot of zone.landings) {
      const dockEdge = spot.dockEdge;
      const park = spot.boatPark;
      const dx = park.x - dockEdge.x;
      const dz = park.z - dockEdge.z;
      const len = Math.hypot(dx, dz) || 1;
      const nx = dx / len;
      const nz = dz / len;
      const g = new T.Group();
      g.name = spot.id === 'main' ? 'landing-' + zone.id : `landing-${zone.id}-${spot.id}`;
      g.userData.noSailBlock = true;
      g.position.set(dockEdge.x + nx * 0.55, water + 0.02, dockEdge.z + nz * 0.55);
      worldGroup.add(g);
      const post = new T.Mesh(new T.CylinderGeometry(.09, .11, 1.5, 7), mat('#c19a6b'));
      post.position.y = .72;
      post.castShadow = true;
      g.add(post);
      // 桩顶圆帽 + 侧挂小旗板：从默认俯视角度也能一眼认出"这里能上岸"。
      const cap = new T.Mesh(new T.SphereGeometry(.17, 10, 7), mat('#f4e6bd'));
      cap.position.y = 1.5;
      cap.castShadow = true;
      g.add(cap);
      box(g, .24, 1.14, 0, .34, .40, .05, '#e2705f');
      const ring = new T.Mesh(new T.TorusGeometry(.46, .075, 6, 18), mat('#e8dcb4'));
      ring.rotation.x = Math.PI / 2;
      ring.position.y = .05;
      g.add(ring);
      for (const [ox, oz] of [[.40, .22], [-.40, -.22], [.22, -.40], [-.22, .40]]) {
        box(g, ox, .06, oz, .16, .07, .16, '#d2564a');
      }
      const key = spot.id === 'main' ? zone.id : `${zone.id}:${spot.id}`;
      landings[key] = { group: g, zone: zone.id, landing: spot.id, name: spot.name };
    }
  }
  gameplay.registerLandingTargets(landings);
  const repairs=[];
  for(let i=0;i<6;i++){const m=box(leftBuildingGroup,1.6+i*.43,3.85,2.3,.39,.18,1.5,'#dbc396');repairs.push(m);}
  return {salvage,dock,aqua,update(t){
    const progress=farm.level>0?1:state.activeJobSite===farm&&state.workerMode==='BUILDING'?state.jobProgress:0;
    repairs.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(progress-i*.055)*5));m.visible=a>0;m.scale.y=Math.max(.001,a);m.position.y=3.85+(1-a)*.45;});plants.forEach((p,i)=>{p.position.y=1.5+Math.sin(t*1.3+i)*.035;});}};
}
