// Readable, solid-colour architecture. Static pieces are batched per material;
// plant roots, water ribbons and construction pieces remain independently animated.
export function refineScene({ THREE: T, worldGroup, makePainterlyMat: material, WATER_LEVEL: water,
  leftBuildingGroup, gardenFlowersGroup, gardenWall, gardenSoil, roofWater,
  upperTowerMesh, upperBackTowerGroup, gameplay }) {
  const { stationPlatformGroup: station, trainCarGroup: train, stationCanopy,
    trackBedGroup, roadBedMesh, zone4Root, euroBuilding, houseBoatGroup, spout, zone3Root: rooftop, planterTowerBody, planterSoil, rooftopSoilPatch, initialPlants,
    underwaterCityGroup, buildSites, state, crops } = gameplay.art;
  const mats = new Map(), parents = new Set(), wind = [], floats = [], flows = [], plots = [], repairs = [];
  const mat = (color, depth = true) => {
    const key = color + depth;
    if (!mats.has(key)) mats.set(key, material(color, {}, depth));
    return mats.get(key);
  };
  function mesh(parent, geometry, color, x, y, z) {
    const m = new T.Mesh(geometry, typeof color === 'string' ? mat(color) : color);
    m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true;
    parent.add(m); parents.add(parent); return m;
  }
  const box = (p,x,y,z,w,h,d,c) => mesh(p,new T.BoxGeometry(w,h,d),c,x,y,z);
  function group(p, x=0, y=0, z=0, name='') {
    const g = new T.Group(); g.position.set(x,y,z); g.name=name; p.add(g); return g;
  }
  function plant(p,x,y,z,size=1,flower=false,phase=0) {
    const g=group(p,x,y,z,'wind-plant');
    box(g,0,.32,0,.07,.64,.07,'#598350');
    for(let i=0;i<4;i++) {
      const a=i*Math.PI/2+phase;
      const leaf=mesh(g,new T.IcosahedronGeometry(1,1),i%2?'#9fbd55':'#568e5d',Math.cos(a)*.24,.25+i*.12,Math.sin(a)*.24);
      leaf.scale.set(.32,.09,.55);leaf.rotation.set(.28,-a+Math.PI/2,.2);
    }
    if(flower) {
      box(g,0,.75,0,.045,.7,.045,'#597e45');
      for(let i=0;i<5;i++) {
        const a=i*1.257;
        const petal=mesh(g,new T.IcosahedronGeometry(.16,1),phase%2?'#e3a3b1':'#f0cd73',Math.cos(a)*.16,1,Math.sin(a)*.16);
        petal.scale.y=.5;
      }
      mesh(g,new T.IcosahedronGeometry(.105,0),'#ad783e',0,1.04,0);
    }
    g.scale.setScalar(size); wind.push({g,phase,base:size});return g;
  }
  function vine(p,x,y,z,length,phase=0) {
    const g=group(p,x,y,z,'hanging-vine');
    for(let i=0;i<length;i++) {
      box(g,Math.sin(i*.8)*.12,-i*.35,0,.055,.42,.055,'#527f54');
      const leaf=mesh(g,new T.IcosahedronGeometry(.25,0),i%2?'#8fae58':'#648e58',i%2?.18:-.16,-i*.35,.04);
      leaf.scale.set(1,.7,.35);
    }
    wind.push({g,phase,base:1});return g;
  }
  function openingWall(p,x,y,z,w,h,rot=0) {
    const g=group(p,x,y,z);g.rotation.y=rot;
    box(g,-w*.38,h*.5,0,w*.24,h,.32,'#d5c9a2');
    box(g,w*.38,h*.36,0,w*.24,h*.72,.32,'#c5bb9a');
    box(g,0,h*.84,0,w,.36,.34,'#e5d7b0');
    box(g,0,.15,0,w,.3,.38,'#a7b9a3');
    box(g,-w*.38,h+.13,0,w*.24,.26,.34,'#eee1ba');
    return g;
  }
  function bed(p,x,y,z,w,d,site=null,stage=0) {
    const g=group(p,x,y,z,'soil-bed');
    const soilMat=material('#956844',{},false);
    const soil=box(g,0,.12,0,w,.24,d,soilMat);soil.userData.noBatch=true;
    for(const side of [-1,1]) {
      box(g,0,.17,side*d/2,w+.18,.35,.14,'#b39a70');
      box(g,side*w/2,.17,0,.14,.35,d,'#c6b18a');
    }
    for(let i=0;i<3;i++) box(g,0,.248,-d*.3+i*d*.3,w*.88,.026,.045,'#8b6749');
    for(let i=0;i<8;i++) {
      const clod=mesh(g,new T.IcosahedronGeometry(.09+(i%3)*.025,0),soilMat,
        Math.sin(i*9.7)*w*.41,.265,Math.cos(i*5.3)*d*.37);
      clod.scale.y=.45;
    }
    const seedlings=[];
    for(let row=0;row<2;row++) for(let col=0;col<3;col++) {
      const root=group(g,-w*.3+col*w*.3,.25,-d*.25+row*d*.5);
      plant(root,0,0,0,.6+(col%2)*.12,true,col+row);
      root.scale.setScalar(site?.001:1);
      root.visible=!site; seedlings.push(root);
    }
    if(site) plots.push({soil,seedlings,site,stage,dry:new T.Color('#956844'),wet:new T.Color('#594535')});
    return g;
  }

  // Circular roof: an annular walkway, radial ribs, four beds and a clear stair landing.
  gardenFlowersGroup.visible=false;
  gardenWall.material=mat('#91b3a1'); gardenSoil.material=mat('#c4baa0');
  roofWater.material=mat('#70b9ae');
  const garden=group(leftBuildingGroup,-.85,4.02,-1,'terraced-roof-garden');
  [[-2,-1.65],[1.5,-1.65],[-2,1.35],[1.5,1.35]].forEach(([x,z])=>bed(garden,x,0,z,2.2,1.65,buildSites.find(s=>s.id==='rooftop_planter'),z>0?1:0));
  box(garden,-.25,.05,0,.85,.1,7.2,'#ded0ab');
  box(garden,0,.05,-.1,7.2,.1,.8,'#ded0ab');
  for(let i=0;i<10;i++) {
    const a=i*Math.PI*2/10;
    const curb=box(leftBuildingGroup,Math.cos(a)*6.15,3.02,Math.sin(a)*6.15,2.3,.4,.22,'#c6d4bd');curb.rotation.y=-a+Math.PI/2;
  }
  for(let i=0;i<6;i++) box(leftBuildingGroup,2.5+i*.35,3.85-i*.18,1.7,1.1,.22,.5,'#d3c9ac');
  for(let i=0;i<4;i++) vine(leftBuildingGroup,-4.6+i*2.1,3.9,3.8,5+i%3,i);
  openingWall(leftBuildingGroup,-1,4.05,-4.55,4,2.4);

  // The rear volume keeps its footprint, but now reads as an open, damaged building.
  upperTowerMesh.visible=false;
  const back=group(upperBackTowerGroup,0,0,0,'open-industrial-ruin');
  box(back,0,.15,0,10.8,.3,8.2,'#adbea7');
  box(back,0,3.5,-1.6,10.8,.32,5,'#b7c2a9');
  for(const x of [-5.1,0,5.1]) for(const z of [-3.8,3.8]) box(back,x,3,z,.48,6,.48,'#c9bb94');
  for(const x of [-3.4,0,3.4]) openingWall(back,x,3.66,-3.8,3.1,3.1);
  openingWall(back,-5.1,3.66,-.4,5.8,3.4,Math.PI/2);
  box(back,0,1.6,4,10.8,3.2,.3,'#d3d0b2');
  for(let i=0;i<4;i++) {
    box(back,-4+i*2.5,6.95,-3.8,1.4,.27,.5,'#e2d0a0');
    plant(back,-4+i*2.5,7.1,-3.8,.7,i%2===0,i);
    vine(back,-4+i*2.7,6.95,-3.5,5+i%3,i);
  }
  // Missing roof is intentional: floor plate, rear window openings and column grid stay visible.

  // The submerged track support is a viaduct, not a single opaque cube.
  roadBedMesh.visible=false;
  box(trackBedGroup,0,-.28,0,17,.46,14,'#76a6a2');
  for(const x of [-7,-2,3,7]) for(const z of [-5.8,5.8]) box(trackBedGroup,x,-6,z,.7,12,.7,'#5c9296');
  for(const y of [-3.2,-7.2]) {
    box(trackBedGroup,0,y,-5.8,16,.5,.7,'#7aa4a0');
    box(trackBedGroup,0,y,5.8,16,.5,.7,'#7aa4a0');
  }
  // Station: supported canopy, platform edge, stair access, bench and readable train windows.
  stationCanopy.scale.z=.58;stationCanopy.position.z=-1.1;
  for(const x of [-2.5,2.4]) {
    box(station,x,1.65,-1.3,.19,2.8,.19,'#57766a');
    box(station,x,2.85,-.7,.16,.18,2.9,'#dbcda5');
    box(station,x,-3,-1.3,.48,6,.48,'#6b9c9e');
  }
  box(station,0,-.48,0,7.9,.3,4.3,'#8caaa1');
  box(station,0,.34,2.02,7.9,.09,.22,'#e7c878');
  for(let i=0;i<7;i++) box(station,-3.5+i, .36,1.72,.65,.07,.16,'#e9ddbb');
  for(let i=0;i<6;i++) box(station,3.2,.2-i*.32,2.5+i*.36,1.4,.32,.6,'#aabfb3');
  box(station,1.6,.75,-.7,1.7,.16,.55,'#b88b58');
  for(const x of [.95,2.25]) box(station,x,.5,-.7,.12,.5,.45,'#527267');
  box(station,1.6,1.13,-.92,1.7,.4,.12,'#c9a270');
  for(const z of [-1.89,1.89]) {
    for(let i=0;i<5;i++) {
      box(train,-2.9+i*1.35,1.18,z,.98,1.08,.06,'#476575');
      box(train,-2.9+i*1.35,1.18,z*1.012,.07,1.07,.07,'#d4dece');
    }
    box(train,0,.47,z,7.8,.1,.08,'#ccbb7e');
    box(train,2.7,.35,z*.99,.7,1.8,.08,'#497b8e');
  }
  const stationSite=buildSites.find(s=>s.id==='yokohama_station');
  bed(station,-1.65,.34,.55,3.1,1.45,stationSite,0);
  bed(train,-.4,2.4,0,3.5,1.6,stationSite,1);

  // Roof slab and building footprint agree; bare soil beds are separated by stone paths.
  planterTowerBody.scale.set(1.32,1,1.32);
  planterTowerBody.material=mat('#7d9f97');
  planterSoil.material=mat('#b8b9a0');rooftopSoilPatch.visible=false;initialPlants.visible=false;
  box(rooftop,0,water+1.38,0,10.6,.36,10.6,'#b9c7af');
  const roofSite=buildSites.find(s=>s.id==='rooftop_planter');
  for(const x of [-2.6,2.6]) for(const z of [-2.6,2]) bed(rooftop,x,water+1.78,z,3.25,2.65,roofSite,z<0?0:1);
  box(rooftop,0,water+1.8,0,1.2,.12,9.7,'#d6caab');
  box(rooftop,0,water+1.8,-.3,9.7,.12,1.1,'#d6caab');
  for(const y of [-1,-4,-7,-10,-13]) {
    box(rooftop,0,y,5.08,10.2,.22,.26,'#afc6b4');
    box(rooftop,-5.08,y,0,.26,.22,10.2,'#afc6b4');
    for(let i=0;i<4;i++) {
      box(rooftop,-3.6+i*2.4,y-1.1,5.02,1.25,1.7,.08,'#385f71');
      box(rooftop,-5.02,y-1.1,-3.6+i*2.4,.08,1.7,1.25,'#385f71');
    }
  }
  openingWall(rooftop,3.1,water+1.9,-4.7,3,2.4);
  vine(rooftop,-5.15,water+2.2,2.1,7,2);
  bed(worldGroup,2.2,2.01,2.4,1.4,1.2,buildSites.find(s=>s.id==='home_cabin'),1);

  // The undeveloped bridge district has an exposed facade and suspended laundry.
  for(const y of [water+4.3,water+1.3,water-1.7,water-4.7]) {
    box(zone4Root,-2.5,y,-6.64,8.6,.18,.22,'#ded2ad');
    for(let i=0;i<3;i++) {
      box(zone4Root,-5.2+i*2.6,y-1.1,.23,1.25,1.7,.08,'#4d7880');
      box(zone4Root,-6.74,y-1.1,-5.2+i*2,.08,1.7,1.1,'#4d7880');
    }
  }
  openingWall(zone4Root,-2.5,water+5.85,-6.3,7.9,1.7);
  for(let i=0;i<3;i++) {
    box(zone4Root,2.4+i*2.8,water-1.1-i*.35,-1.2+i*1.4,.55,8,.55,'#78978d');
    vine(zone4Root,1.7+i*2.8,water+3.2-i*.45,.9+i*1.4,6,i);
  }
  box(houseBoatGroup,0,1.35,.77,1.4,.65,.06,'#4a7686');
  for(const x of [-.95,.95]) box(houseBoatGroup,x,1.35,-.3,.06,.65,1.4,'#4a7686');
  const laundry=houseBoatGroup.children.filter(m=>m.isMesh && m.geometry.parameters?.width===.06);
  laundry.forEach((m,i)=>wind.push({g:m,phase:i*1.4,base:1}));
  // Different ruin silhouettes: open room, broken arcade, stair remnant, partial floor stack.
  underwaterCityGroup.visible=false;
  const ruins=group(worldGroup,0,0,0,'ruin-district');
  const specs=[[-28,1.3,-35,0],[20,1.2,-36,1],[-30,1.3,32,2],[34,1.3,32,3],[-5,1.3,39,0]];
  specs.forEach(([x,y,z,type],n)=>{
    const g=group(ruins,x,y,z,`ruin-${type}-${n}`);g.rotation.y=n*.37;
    const w=4.6+(n%2)*1.2,d=4.3;
    // Visible slab edges and open bays, with a dark core only far below the surface.
    box(g,0,-13,0,w,10,d,'#377d91');
    for(let floor=0;floor<3;floor++) {
      const fy=-floor*2.9;
      box(g,type===3&&floor===0?-.8:0,fy,0,type===3&&floor===0?w*.65:w,.26,d,'#85b4ad');
      for(const px of [-w/2+.25,w/2-.25]) for(const pz of [-1.9,1.9]) box(g,px,fy-1.4,pz,.4,2.9,.4,'#6ba39f');
      box(g,0,fy-1.3,-1.9,w,.8,.25,'#547f91');
    }
    if(type===0) {
      openingWall(g,0,.15,-1.85,w,2.8);openingWall(g,-w/2+.2,.15,0,3.8,1.9,Math.PI/2);
    } else if(type===1) {
      for(let i=0;i<3;i++) box(g,-w*.4+i*w*.4,1.4,-1.7,.45,2.8,.45,'#d3c7a2');
      box(g,-.4,2.6,-1.7,w*.8,.4,.45,'#e4d5af');
    } else if(type===2) {
      for(let i=0;i<7;i++) box(g,-w*.45,-i*.29,1.7+i*.37,1.5,.27,.55,'#8bb7ad');
      box(g,w*.3,1.2,-1.5,.6,2.4,.6,'#cfbd98');
    } else {
      openingWall(g,w*.35,.1,0,3.6,3.3,Math.PI/2);
      const slab=box(g,-.9,.48,.5,2.7,.25,1.5,'#b6c3aa');slab.rotation.z=-.27;
    }
    for(let i=0;i<3;i++) {
      const block=box(g,-w*.3+i*w*.3,.3,1.2-(i%2)*.6,.62,.35,.55,'#c4c5a6');block.rotation.y=i*.8;
    }
    if(y>0) {
      plant(g,w*.3,.3,1,.7,true,n);vine(g,-w*.45,.2,1.95,5+n%3,n);
    } else vine(g,w*.4,-.2,1.8,6,n);
  });

  // Only repair pieces assemble; existing ruins never pop away.
  for(const [site,parent,y] of [[stationSite,station,.4],[roofSite,rooftop,water+1.9]]) {
    const pieces=[];
    for(let i=0;i<8;i++) {
      const m=box(parent,-3.2+i*.85,y,-1.9,.73,.12,.9,'#bd966b');m.userData.noBatch=true;
      m.visible=false;pieces.push({m,y:m.position.y,start:i*.055});
    }
    repairs.push({site,pieces});
  }
  // Replace legacy whole-group scaling with growth rooted in each plant's own base.
  crops.forEach(g=>{g.visible=false;g.userData.replaced=true;});
  buildSites.forEach(site=>site.stages.forEach((stage,index)=>{
    if(!stage.applyVisual)return;
    stage.applyVisual=function(progress){ this.visualProgress=progress; };
  }));

  // A small working windmill, wind pennants, flowing water and floating leaves.
  const rotor=group(rooftop,4.4,water+4.6,3.4,'windmill-rotor');
  box(rooftop,4.4,water+3.1,3.4,.12,3,.12,'#7b8871');
  for(let i=0;i<4;i++) {const blade=box(rotor,0,.47,0,.2,.8,.08,'#e0c887');blade.rotation.z=i*Math.PI/2;blade.position.set(-Math.sin(i*Math.PI/2)*.47,Math.cos(i*Math.PI/2)*.47,0);}
  const flag=mesh(station,new T.PlaneGeometry(.9,.5,6,2),mat('#dba276',false),-2.5,2.6,-1.15);flag.material.side=T.DoubleSide;flag.userData.noBatch=true;
  const flagBase=flag.geometry.attributes.position.array.slice();
  for(const [x,z] of [[-14,4],[-12,7],[11,8],[13,-5],[-20,8]]) {
    const g=group(worldGroup,x,water+.06,z,'floating-leaf');
    const leaf=mesh(g,new T.CylinderGeometry(.34,.34,.035,12,1,false,.3,5.8),'#8fb969',0,0,0);
    floats.push({g,x,z,phase:x*.4});
  }
  for(let i=0;i<6;i++) {
    const x=-28+i*.7,z=-16+(i%2)*.8;
    const g=group(worldGroup,x,water+.1,z,'restored-lotus');
    mesh(g,new T.CylinderGeometry(.3,.3,.035,10),'#91b765',0,0,0);
    const flower=mesh(g,new T.IcosahedronGeometry(.16,1),'#e8b0c4',0,.14,0);flower.scale.y=.65;
    floats.push({g,x,z,phase:i,site:stationSite,stage:2});
  }
  for(const [x,y,z] of [[-3.5,2.7,-2.5],[13,2.8,8]]) {
    const ribbon=mesh(worldGroup,new T.PlaneGeometry(.2,1.7,1,8),mat('#9eddd4',false),x,y,z);
    ribbon.material.side=T.DoubleSide;ribbon.userData.noBatch=true;
    flows.push({m:ribbon,base:ribbon.geometry.attributes.position.array.slice()});
  }
  const drops=group(worldGroup,0,0,0,'watering-drops');
  for(let i=0;i<8;i++) mesh(drops,new T.IcosahedronGeometry(.055,0),'#a8dce0',0,0,0).userData.noBatch=true;

  // Merge static subparts without merging animation roots or changing hit areas.
  for(const p of parents) {
    const buckets=new Map();
    for(const m of [...p.children]) {
      if(!m.isMesh||m.userData.noBatch||Array.isArray(m.material))continue;
      if(!buckets.has(m.material))buckets.set(m.material,[]);buckets.get(m.material).push(m);
    }
    for(const [material,items] of buckets) {
      if(items.length<2)continue;
      const attributes={position:[],normal:[],uv:[]};
      for(const m of items) {
        m.updateMatrix();const geo=m.geometry.index?m.geometry.toNonIndexed():m.geometry.clone();geo.applyMatrix4(m.matrix);
        for(const key of Object.keys(attributes)) attributes[key].push(geo.attributes[key].array);
        geo.dispose();p.remove(m);m.geometry.dispose();
      }
      const geo=new T.BufferGeometry();
      for(const [key,arrays] of Object.entries(attributes)) {
        const a=new Float32Array(arrays.reduce((sum,v)=>sum+v.length,0));let offset=0;
        arrays.forEach(v=>{a.set(v,offset);offset+=v.length;});geo.setAttribute(key,new T.BufferAttribute(a,key==='uv'?2:3));
      }
      const merged=new T.Mesh(geo,material);merged.castShadow=true;merged.receiveShadow=true;p.add(merged);
    }
  }
  const dry=new T.Color('#956844'),wet=new T.Color('#594535');
  const smooth=(a,b,v)=>T.MathUtils.smoothstep(v,a,b);
  function progress(site,stage) {
    if(site.level>stage)return 1;
    return site.level===stage&&state.activeJobSite===site&&state.workerMode==='BUILDING'?state.jobProgress:0;
  }
  function update(t) {
    wind.forEach(({g,phase})=>{g.rotation.z=Math.sin(t*1.2+phase)*.045;g.rotation.x=Math.sin(t*.8+phase)*.025;});
    rotor.rotation.z=-t*.7;
    const pos=flag.geometry.attributes.position;
    for(let i=0;i<pos.count;i++) pos.setZ(i,flagBase[i*3+2]+Math.sin(t*2.1+flagBase[i*3]*4)*.09*(flagBase[i*3]+.5));pos.needsUpdate=true;
    floats.forEach(({g,x,z,phase,site,stage})=>{if(site){const a=smooth(.3,1,progress(site,stage));g.visible=a>0;g.scale.setScalar(Math.max(.001,a));}g.position.set(x+Math.sin(t*.35+phase)*.12,water+.07+Math.sin(t*1.5+phase)*.045,z+Math.cos(t*.3+phase)*.1);g.rotation.z=Math.sin(t+phase)*.05;});
    flows.forEach(({m,base})=>{const a=m.geometry.attributes.position;for(let i=0;i<a.count;i++)a.setX(i,base[i*3]+Math.sin(t*5+base[i*3+1]*6)*.04);a.needsUpdate=true;});
    plots.forEach(({soil,seedlings,site,stage})=>{
      const p=progress(site,stage);soil.material.color.lerpColors(dry,wet,smooth(.14,.4,p));
      seedlings.forEach((g,i)=>{const growth=smooth(.35+i*.035,.83+i*.025,p);g.visible=growth>0;g.scale.set(.25+growth*.75,Math.max(.001,growth),.25+growth*.75);});
    });
    repairs.forEach(({site,pieces})=>pieces.forEach(({m,y,start})=>{
      const p=progress(site,0);const a=smooth(start,start+.16,p);m.visible=a>0;m.scale.set(1,Math.max(.001,a),1);m.position.y=y+(1-a)*.45;
    }));
    const active=state.activeJobSite;const watering=active&&state.workerMode==='BUILDING'&&state.jobProgress>.14&&state.jobProgress<.8;
    drops.visible=!!watering;
    if(watering) {
      spout.getWorldPosition(drops.position);
      drops.children.forEach((d,i)=>{const f=(t*1.4+i/8)%1;d.position.set(f*.45,-f*.6,Math.sin(i*2)*.1+f*.3);});
    }
  }
  return {update,plots,repairs,ruins,wind,rotor,flows};
}
