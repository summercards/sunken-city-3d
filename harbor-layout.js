// Core islands have breathing room; distant districts remain available when sailing.
export function arrangeHarbor({ THREE:T, worldGroup, gameplay, sceneArt, leftBuildingGroup, poleGroup, makePainterlyMat:mat, WATER_LEVEL:water }) {
  const {buildSites,state,zone3Root}=gameplay.art;
  leftBuildingGroup.position.set(-18,.3,-4);
  zone3Root.visible=false;
  // Carry the animated windmill onto the farm rather than leaving it on the retired roof.
  leftBuildingGroup.add(sceneArt.rotor);sceneArt.rotor.position.set(3.8,6.6,0);
  const farm=buildSites.find(s=>s.id==='rooftop_planter');
  farm.hitRoots=[leftBuildingGroup];farm.hoverAnchor.set(-18,5.2,-4);
  // Remove redundant underwater filler from the navigable channels.
  worldGroup.children.filter(g=>g.userData.legacyTower).forEach(g=>{
    if(g.position.x<0) g.visible=false;
  });
  const box=(p,x,y,z,w,h,d,color)=>{const m=new T.Mesh(new T.BoxGeometry(w,h,d),mat(color));m.position.set(x,y,z);p.add(m);return m;};
  function island(name,x,z,w,d){const g=new T.Group();g.name=name;g.position.set(x,0,z);worldGroup.add(g);
    box(g,0,.9,0,w,.5,d,'#a9c6b5');
    for(const sx of [-1,1])for(const sz of [-1,1])box(g,sx*(w/2-.4),-3,sz*(d/2-.4),.45,8,.45,'#639fa1');return g;}
  const salvage=island('C · 绞盘打捞台',-12,13,6.5,5.5);
  for(let i=0;i<10;i++)box(salvage,-2.9+i*.64,1.24,0,.58,.18,5.3,'#c49c6e');
  poleGroup.position.set(-12,-4.5,13);poleGroup.scale.setScalar(.72);
  box(salvage,1.5,1.7,-1.2,1.4,.9,1.2,'#d8b879');
  box(salvage,1.5,2.2,-1.2,1.5,.12,1.3,'#ede0b6');
  const dock=island('D · 交易码头',.3,9,5,4);
  for(let i=0;i<8;i++)box(dock,-2.15+i*.62,1.3,0,.55,.16,4,'#d5a56d');
  for(const x of [-2,2])box(dock,x,1.7,1.5,.25,1.1,.25,'#806951');
  // Short gangway connects the home shore to the dedicated dock.
  const bridge=box(worldGroup,1.8,1.55,6.1,1.5,.2,3.2,'#d6b887');bridge.rotation.y=-.4;
  box(leftBuildingGroup,3.8,5.1,0,.16,3,.16,'#8d9577');
  const aqua=island('E · 浅水养殖台',16,15,6.5,5.5);
  const plants=[];
  for(const x of [-1.6,1.6])for(const z of [-1.3,1.3]){
    box(aqua,x,1.23,z,2.7,.25,2.1,'#6ba69b');box(aqua,x,1.38,z,2.25,.08,1.65,'#4b989e');
    for(let i=0;i<3;i++){const p=new T.Mesh(new T.SphereGeometry(.35,6,4),mat('#a9c86e'));p.position.set(x-.6+i*.6,1.5,z);p.scale.set(1,.24,.7);p.visible=false;aqua.add(p);plants.push(p);}
  }
  const aquaSite={id:'shallow_aquaculture',zone:'zone5',name:'浅水养殖台',hitRoots:[aqua],hoverAnchor:new T.Vector3(16,2.5,15),boatParkPos:new T.Vector3(11,water,12),shoreEdgePos:new T.Vector3(13,1.8,14),buildStandPos:new T.Vector3(15,1.8,15),level:0,maxLevel:1,storedCoins:0,coinsPerCycle:0,stages:[{cost:35,materials:{wood:3,parts:2,pearl:1},requires:{boat2:2},rateAdd:2,desc:'用远海珍珠培育浅水池，消耗3木料、2旧零件与1珍珠。船只2级后开放修建。',applyVisual(p){plants.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(p-.35-i*.025)*3));m.visible=a>0;m.scale.set(a,.24*a,.7*a);});}}]};
  buildSites.push(aquaSite);
  // Harbor targets are consumed by the single click router in gameplay.js.
  salvage.poleGroup = poleGroup;
  gameplay.registerHarborTargets({ salvage, dock });
  const repairs=[];
  for(let i=0;i<6;i++){const m=box(leftBuildingGroup,1.6+i*.43,3.85,2.3,.39,.18,1.5,'#dbc396');repairs.push(m);}
  return {salvage,dock,aqua,update(t){
    const progress=farm.level>0?1:state.activeJobSite===farm&&state.workerMode==='BUILDING'?state.jobProgress:0;
    repairs.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(progress-i*.055)*5));m.visible=a>0;m.scale.y=Math.max(.001,a);m.position.y=3.85+(1-a)*.45;});plants.forEach((p,i)=>{p.position.y=1.5+Math.sin(t*1.3+i)*.035;});}};
}
