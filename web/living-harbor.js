// Layered restoration art. Shared geometry/materials are instanced per local group.
export function polishHarbor({THREE:T,worldGroup,gameplay,sceneArt,houseGroup,cabinMesh,lowerRoof,leftBuildingGroup,upperBackTowerGroup,poleGroup,makePainterlyMat:make,WATER_LEVEL:water}) {
  const {state,buildSites}=gameplay.art,home=buildSites.find(s=>s.id==='home_cabin'),farm=buildSites.find(s=>s.id==='rooftop_planter');
  const layers=[],sway=[],floaters=[],parents=new Set(),materials=new Map();
  const geo={box:new T.BoxGeometry(1,1,1),leaf:new T.IcosahedronGeometry(1,1),cyl:new T.CylinderGeometry(1,1,1,8),cone:new T.ConeGeometry(1,1,10)};
  function mat(c){if(!materials.has(c))materials.set(c,make(c,{},true));return materials.get(c);}
  function group(p,x=0,y=0,z=0,name=''){const g=new T.Group();g.position.set(x,y,z);g.name=name;p.add(g);return g;}
  function piece(p,type,x,y,z,sx,sy,sz,c){const m=new T.Mesh(geo[type],mat(c));m.position.set(x,y,z);m.scale.set(sx,sy,sz);m.castShadow=true;m.receiveShadow=true;p.add(m);parents.add(p);return m;}
  const box=(p,x,y,z,w,h,d,c)=>piece(p,'box',x,y,z,w,h,d,c);
  function layer(p,site,stage,x,y,z,name,start=.3){const g=group(p,x,y,z,name);layers.push({g,site,stage,start});return g;}
  function foliage(p,x,y,z,size=1,flowers=false){const g=group(p,x,y,z,'foliage');g.scale.setScalar(size);sway.push({g,phase:x*1.8+z});
    for(let i=0;i<7;i++){const a=i*2.4;const leaf=piece(g,'leaf',Math.sin(a)*.32,.28+(i%3)*.15,Math.cos(a)*.32,.17,.08,.47,i%2?'#9ac650':'#4d985c');leaf.rotation.set(.25,a,-.18);
      if(flowers&&i%2===0){const bloom=group(g,Math.sin(a)*.40,.70+(i%2)*.15,Math.cos(a)*.40);for(let j=0;j<5;j++){const b=j*1.257;piece(bloom,'leaf',Math.sin(b)*.13,0,Math.cos(b)*.13,.15,.08,.12,i%3?'#f4e8af':'#ef97b1');}piece(bloom,'leaf',0,.04,0,.08,.06,.08,'#e9b656');}}
    return g;
  }
  function pot(p,x,y,z,size=1){const g=group(p,x,y,z);piece(g,'cyl',0,.24,0,.32,.48,.32,'#d9b68b');piece(g,'cyl',0,.49,0,.35,.10,.35,'#f2ddbd');piece(g,'cyl',0,.53,0,.29,.04,.29,'#79523d');g.scale.setScalar(size);return g;}
  function vine(p,x,y,z,length,flower=false){const g=group(p,x,y,z,'flowering-vine');sway.push({g,phase:x+z});
    for(let i=0;i<length;i++){box(g,Math.sin(i*.7)*.12,-i*.27,0,.045,.32,.045,'#5d8548');piece(g,'leaf',i%2?.15:-.15,-i*.27,.03,.21,.15,.09,i%2?'#a9c858':'#649d4d');
      if(flower&&i%3===0)piece(g,'leaf',.12,-i*.27,.16,.17,.15,.12,'#ed98b2');}return g;
  }
  function rope(p,a,b){const mid=a.clone().lerp(b,.5);mid.y-=.12;const curve=new T.QuadraticBezierCurve3(a,mid,b);const m=new T.Mesh(new T.TubeGeometry(curve,10,.035,5,false),mat('#dfd0a2'));p.add(m);return m;}
  function rail(p,points){for(const [x,y,z]of points){box(p,x,y,z,.14,.85,.14,'#bb915c');box(p,x,y+.44,z,.22,.1,.22,'#ead6ae');}
    for(let i=1;i<points.length;i++)rope(p,new T.Vector3(...points[i-1]).add(new T.Vector3(0,.25,0)),new T.Vector3(...points[i]).add(new T.Vector3(0,.25,0)));}
  // A simple cream dwelling, warm timber ledges and a welcoming striped awning.
  cabinMesh.material=[mat('#e9d8b5'),mat('#b9c5b4'),mat('#d6cdb0'),mat('#94aa9e'),mat('#efdfbb'),mat('#b9c8b5')];
  lowerRoof.material=mat('#c2b388');
  const base=group(houseGroup,0,0,0,'cabin-craft');
  box(base,0,.14,2.47,5.55,.27,.25,'#b98c59');box(base,0,3.32,2.46,5.6,.16,.2,'#d9b67b');
  for(const x of [-2.65,2.65])box(base,x,1.65,2.47,.16,3.15,.18,'#c8a56e');
  const awning=group(base,.75,2.85,2.8,'striped-awning');awning.rotation.x=.10;
  for(let i=0;i<7;i++){box(awning,-1.5+i*.5,0,0,.50,.09,1.45,i%2?'#f9edc3':'#e6bc5c');piece(awning,'cyl',-1.5+i*.5,-.12,.70,.25,.14,.14,i%2?'#f9edc3':'#e6bc5c').rotation.z=Math.PI/2;}
  for(const x of [-.85,2.35])box(base,x,2.37,3.4,.07,.8,.07,'#b29360');
  // Round side window and wooden crossbar, visibly inset into the side wall.
  const round=group(base,-2.76,1.95,-.95);round.rotation.y=-Math.PI/2;
  const rim=new T.Mesh(new T.TorusGeometry(.58,.075,6,20),mat('#dcb36d'));round.add(rim);
  const glass=new T.Mesh(new T.CircleGeometry(.51,20),mat('#397d88'));glass.position.z=-.02;round.add(glass);
  box(round,0,0,.025,.055,1.03,.06,'#e1bf7d');box(round,0,0,.025,1.03,.055,.06,'#e1bf7d');
  // A ladder beside the roof garden, planter boxes and low dock ropes.
  for(const x of [2.70,3.18])box(base,x,2.4,.65,.10,4.3,.10,'#c09b62');
  for(let i=0;i<10;i++)box(base,2.94,.55+i*.40,.65,.48,.075,.12,'#e6c798');
  rail(base,[[-2.35,.9,4.5],[-1.1,.9,4.5]]);rail(base,[[1.65,.9,4.5],[2.8,.9,4.5],[2.8,.9,3.5]]);
  for(const [x,z]of [[-2.2,2.9],[2.3,2.9],[-2.1,-1.6]])pot(base,x,.3,z,.8);
  const domestic=layer(houseGroup,home,1,0,0,0,'restored-home',.16);
  box(domestic,-1.9,.68,3.2,.8,.12,.45,'#e4c08b');for(const x of [-2.2,-1.6])box(domestic,x,.42,3.2,.08,.45,.08,'#a07e53');
  const roofGarden=layer(houseGroup,home,1,0,4.1,-1.45,'roof-bloom',.38);
  for(const x of [-2.25,2.25]){pot(roofGarden,x,0,0,.8);foliage(roofGarden,x,.45,0,1.7,true);vine(roofGarden,x,0,.65,9,true);}
  for(let i=0;i<5;i++){const g=layer(houseGroup,home,1,-2.6+i*1.25,3.35,2.6,'facade-bloom',.42+i*.055);foliage(g,0,0,0,.8,true);vine(g,0,-.1,0,5+i%3,true);}
  for(const [x,z]of [[-2.2,2.9],[2.3,2.9],[-2.1,-1.6]]){const g=layer(houseGroup,home,1,x,.75,z,'doorstep-garden',.28);foliage(g,0,0,0,.7,true);}
  // The rear ruin reads as an arcade; its hard graffiti block becomes a quiet plaster wall.
  const back=upperBackTowerGroup.getObjectByName('open-industrial-ruin');
  if(back){for(const m of back.children)if(m.isMesh&&m.position.z===4)m.material=mat('#d3d0b2');
    for(const x of [-3.4,0,3.4]){box(back,x,1.7,4.17,1.4,1.8,.08,'#447b84');box(back,x,.77,4.23,1.65,.18,.24,'#d9caa8');box(back,x,1.7,4.26,.07,1.85,.08,'#d7c395');}
  }
  if(back){
    const terrace=layer(back,home,1,0,3.7,0,'upper-terrace-garden',.25);
    for(const x of [-3.8,-1.3,1.3,3.8]){box(terrace,x,.22,.45,1.6,.44,1.1,'#c7af82');box(terrace,x,.46,.45,1.4,.05,.9,'#775943');foliage(terrace,x,.52,.45,1.6,true);vine(terrace,x,.4,1.0,8,true);}
    rail(terrace,[[-4.8,.6,1.15],[-2.4,.6,1.15],[0,.6,1.15],[2.4,.6,1.15],[4.8,.6,1.15]]);
  }
  // Bare farm retains broken parapets and soil. Restoration adds rails, then a shade tree.
  const rubble=group(leftBuildingGroup,0,4.15,0,'loose-rubble');
  for(let i=0;i<7;i++){const b=box(rubble,Math.sin(i*2.3)*4.5,0,Math.cos(i*2.3)*3.9,.42,.17,.25,'#b9b9a1');b.rotation.y=i;}
  const repaired=layer(leftBuildingGroup,farm,0,0,4.1,0,'farm-repaired',.05);
  const points=[];for(let i=0;i<12;i++){const a=-.2+i*.35;points.push([Math.cos(a)*5.3,.5,Math.sin(a)*5.3]);}rail(repaired,points);
  box(repaired,3.7,.50,-.9,1.3,.15,.6,'#c8a16b');box(repaired,3.7,.86,-1.15,1.3,.48,.10,'#dfbe86');
  for(const x of [3.25,4.15])box(repaired,x,.28,-.9,.12,.5,.5,'#9c8057');
  const shade=layer(leftBuildingGroup,farm,1,2.8,4.2,-2.4,'farm-shade',.18);
  piece(shade,'cyl',0,1.05,0,.055,2.1,.055,'#bc996a');
  for(let i=0;i<8;i++){const g=new T.ConeGeometry(1.5,.48,3,1,true,i*Math.PI/4,Math.PI/4);const m=new T.Mesh(g,mat(i%2?'#f2e4b3':'#de9e77'));m.material.side=T.DoubleSide;m.position.y=2.2;shade.add(m);}
  const tree=layer(leftBuildingGroup,farm,1,-3.0,4.15,-2.4,'farm-tree',.35);
  pot(tree,0,0,0,1.6);piece(tree,'cyl',0,1.25,0,.17,1.7,.17,'#9a7852');
  for(let i=0;i<7;i++){const a=i*2.4;piece(tree,'leaf',Math.sin(a)*.65,2.3+(i%3)*.25,Math.cos(a)*.65,.95,.65,.85,i%2?'#95bb50':'#6fa653');}
  sway.push({g:tree,phase:2});
  for(let i=0;i<12;i++){const a=i*.52;const g=layer(leftBuildingGroup,farm,i%3===0?0:1,Math.cos(a)*5.55,4.05,Math.sin(a)*5.55,'garden-edge',.30+(i%4)*.09);foliage(g,0,0,0,1.15,i%3!==0);vine(g,0,-.15,0,8+i%6,i%2===0);}
  // Architectural rhythm: deep window recesses, projecting cream floor bands and shutters.
  const facade=group(leftBuildingGroup,0,0,0,'rounded-arcade-facade');
  for(let row=0;row<5;row++)for(let i=0;i<20;i++){
    const a=i*Math.PI/10,y=1.45-row*2.8;
    const bay=group(facade,Math.cos(a)*6.28,y,Math.sin(a)*6.28);bay.rotation.y=-a+Math.PI/2;
    box(bay,0,0,0,1.57,1.8,.12,'#356e7e');
    box(bay,-.87,0,.10,.20,2.8,.30,'#b8cbbc');
    box(bay,0,-1.02,.16,1.92,.40,.45,'#d7d7b9');
    box(bay,0,0,.11,.075,1.8,.13,'#a2c3ba');
    if(row===0&&i%3===0){box(bay,.7,0,.22,.30,1.8,.13,'#70a9a7');box(bay,0,.98,.28,1.9,.16,.62,'#e0cba4');}
  }
  const lushFacade=layer(leftBuildingGroup,farm,1,0,0,0,'cascading-flower-balconies',.42);
  for(let i=0;i<10;i++){
    const a=i*Math.PI/5;const g=group(lushFacade,Math.cos(a)*6.45,3.7,Math.sin(a)*6.45);g.rotation.y=-a+Math.PI/2;
    box(g,0,-.15,0,1.25,.4,.50,'#c5b087');foliage(g,0,.1,0,1.3,true);vine(g,-.3,-.2,.2,15+i%4,true);
  }
  // Rear dwelling: readable inset windows, blue shutters, timber balconies and a planted upper room.
  if(back){
    for(const x of [-3.4,0,3.4]){
      for(const z of [4.27,-3.96]){const g=group(back,x,1.65,z);if(z<0)g.rotation.y=Math.PI;
        box(g,0,0,0,1.35,1.9,.12,'#327787');for(const side of [-1,1])box(g,side*.88,0,.1,.32,1.95,.14,'#76aeb0');
        box(g,0,0,.12,.08,1.9,.08,'#deb983');box(g,0,0,.12,1.35,.08,.08,'#deb983');
        box(g,0,-1.1,.45,2.35,.20,1.25,'#c99b6a');rail(g,[[-1,-.55,.95],[0,-.55,.95],[1,-.55,.95]]);
      }
    }
    const room=group(back,1.3,3.75,-1.65,'terrace-studio');
    box(room,0,1.25,0,3.7,2.5,2.7,'#e4dbc0');box(room,0,2.55,0,4.1,.24,3.1,'#c5b88d');
    for(const x of [-.9,.9]){box(room,x,1.3,1.38,.95,1.5,.08,'#4b929c');box(room,x,1.3,1.46,.07,1.5,.08,'#d8b37a');}
    const lush=layer(back,home,1,0,0,0,'rear-house-climbers',.4);
    for(const x of [-4.8,-1.4,4.6]){foliage(lush,x,3.8,3.8,1.6,true);vine(lush,x,3.65,4.3,15,true);}
  }
  // Replace the small orange spool silhouette with a full timber utility pole.
  for(const child of poleGroup.children)child.visible=false;
  poleGroup.scale.setScalar(.9);
  poleGroup.rotation.y=-Math.PI/4;
  const utility=group(poleGroup,0,0,0,'crafted-utility-pole');
  piece(utility,'cyl',0,-1.25,0,.34,37.5,.34,'#ad7849');piece(utility,'cyl',0,17.55,0,.39,.18,.39,'#dbb172');
  box(utility,0,15.1,0,4.3,.32,.38,'#bf8a53');
  for(const x of [-1.6,1.6]){box(utility,x,15.55,0,.16,.75,.16,'#65767a');for(const y of [15.5,15.8])piece(utility,'cyl',x,y,0,.24,.14,.24,'#d1ded0');}
  for(const y of [7.5,11,14.7])for(let i=0;i<3;i++){const ring=new T.Mesh(new T.TorusGeometry(.36,.055,5,12),mat('#d6bd8d'));ring.rotation.x=Math.PI/2;ring.position.y=y+i*.14;utility.add(ring);}
  const drum=group(utility,.75,12.7,.25,'working-pulley');
  piece(drum,'cyl',0,0,0,.65,1.8,.65,'#555d60').rotation.z=Math.PI/2;
  for(const x of [-.95,.95])piece(drum,'cyl',x,0,0,.91,.18,.91,'#c2925b').rotation.z=Math.PI/2;
  for(let i=0;i<8;i++){const ring=new T.Mesh(new T.TorusGeometry(.67,.075,6,16),mat('#353f48'));ring.rotation.y=Math.PI/2;ring.position.x=-.7+i*.20;drum.add(ring);}
  box(drum,1.15,-.45,0,.16,1,.16,'#916b43');piece(drum,'cyl',1.45,-.9,0,.13,.65,.13,'#e1b879').rotation.z=Math.PI/2;
  const bird=group(utility,0,18,0,'perched-gull');piece(bird,'leaf',0,0,0,.42,.28,.6,'#f7f1d8');piece(bird,'leaf',0,.33,-.28,.23,.25,.25,'#fff7dc');box(bird,0,.31,-.58,.12,.1,.30,'#dfb255');
  piece(bird,'leaf',.18,.08,.1,.25,.13,.45,'#899b9c');
  const poleGreen=layer(utility,home,1,0,0,0,'pole-flowering-climber',.35);
  vine(poleGreen,.34,12,.28,18,true);const basket=pot(poleGreen,0,8,.45,1.6);foliage(basket,0,.6,0,1.2,true);
  // Existing decoration also participates in restoration instead of starting fully grown.
  const oldVines=leftBuildingGroup.children.filter(g=>g.name==='hanging-vine');
  oldVines.forEach(g=>layers.push({g,site:farm,stage:0,start:.4}));
  // Floating timber, a barrel and salvaged cars all share bounded buoyancy, never drift into routes.
  for(const [x,z,yaw]of [[-9,10,.5],[12,10,-.4],[-23,4,1.1]]){
    const g=group(worldGroup,x,water+.06,z,'driftwood');g.rotation.y=yaw;
    for(let i=0;i<3;i++){const log=piece(g,'cyl',i*.30,0,0,.14,1.6+i*.25,.14,i%2?'#ad8b5b':'#c2a375');log.rotation.x=Math.PI/2;}
    for(const z of [-.5,.5])box(g,.3,.12,z,.95,.045,.055,'#8a8667');floaters.push({g,base:g.position.clone(),yaw,phase:x*.3});
  }
  worldGroup.traverse(g=>{if(g.userData.buoyant)floaters.push({g,base:g.position.clone(),yaw:g.rotation.y,phase:g.position.x*.8});});
  // Batch the static curved facade across bay transforms, keeping growing plants independent.
  facade.updateWorldMatrix(true,true);
  const facadeInverse=facade.matrixWorld.clone().invert(), facadeBuckets=new Map();
  facade.traverse(m=>{if(m.isMesh){const key=m.geometry.uuid+m.material.uuid;if(!facadeBuckets.has(key))facadeBuckets.set(key,[]);facadeBuckets.get(key).push(m);}});
  for(const meshes of facadeBuckets.values()){
    const inst=new T.InstancedMesh(meshes[0].geometry,meshes[0].material,meshes.length);
    meshes.forEach((m,i)=>{inst.setMatrixAt(i,new T.Matrix4().multiplyMatrices(facadeInverse,m.matrixWorld));m.parent.remove(m);});
    inst.castShadow=true;inst.receiveShadow=true;inst.computeBoundingSphere();facade.add(inst);
  }
  // Group-local instancing reduces added foliage and structure to a small number of draws.
  for(const parent of parents){const buckets=new Map();for(const m of [...parent.children])if(m.isMesh&&Object.values(geo).includes(m.geometry)){
    const key=m.geometry.uuid+m.material.uuid;if(!buckets.has(key))buckets.set(key,[]);buckets.get(key).push(m);}
    for(const meshes of buckets.values())if(meshes.length>1){const inst=new T.InstancedMesh(meshes[0].geometry,meshes[0].material,meshes.length);meshes.forEach((m,i)=>{m.updateMatrix();inst.setMatrixAt(i,m.matrix);parent.remove(m);});inst.castShadow=true;inst.receiveShadow=true;inst.computeBoundingSphere();parent.add(inst);}
  }
  function progress(site,stage){return site.level>stage?1:site.level===stage&&state.activeJobSite===site&&state.workerMode==='BUILDING'?state.jobProgress:0;}
  function update(t){
    layers.forEach(({g,site,stage,start})=>{const a=T.MathUtils.smoothstep(progress(site,stage),start,Math.min(1,start+.38));g.visible=a>.001;g.scale.setScalar(Math.max(.001,a));});
    rubble.visible=farm.level===0&&progress(farm,0)<.45;
    sway.forEach(({g,phase})=>{g.rotation.z=Math.sin(t*.9+phase)*.025;g.rotation.x=Math.cos(t*.7+phase)*.018;});
    drum.rotation.x=Math.sin(t*.45)*.10; bird.rotation.y=Math.sin(t*.35)*.15;
    floaters.forEach(({g,base,yaw,phase})=>{g.position.set(base.x+Math.sin(t*.21+phase)*.12,base.y+Math.sin(t*1.1+phase)*.08,base.z+Math.cos(t*.18+phase)*.12);g.rotation.set(Math.sin(t*.85+phase)*.025,yaw+Math.sin(t*.22+phase)*.035,Math.cos(t*1.05+phase)*.035);});
  }
  update(0);return {update,layers,floaters,rubble};
}
