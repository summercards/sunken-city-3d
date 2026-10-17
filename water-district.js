// Sparse peripheral silhouettes and submerged architecture; real roof heights drive water depth.
export function createWaterDistrict({THREE:T,worldGroup,makePainterlyMat:make}) {
  const root=new T.Group();root.name='layered-water-district';worldGroup.add(root);
  const mats=new Map(),parents=new Set(),wind=[];
  const geometries={box:new T.BoxGeometry(1,1,1),leaf:new T.IcosahedronGeometry(1,0),cyl:new T.CylinderGeometry(1,1,1,32),cone:new T.ConeGeometry(1,1,8)};
  function mat(c){if(!mats.has(c))mats.set(c,make(c,{},true));return mats.get(c);}
  function group(p,x,y,z,name){const g=new T.Group();g.name=name;g.position.set(x,y,z);p.add(g);return g;}
  function piece(p,type,x,y,z,w,h,d,c){const m=new T.Mesh(geometries[type],mat(c));m.position.set(x,y,z);m.scale.set(w,h,d);m.castShadow=true;m.receiveShadow=true;p.add(m);parents.add(p);return m;}
  const box=(p,x,y,z,w,h,d,c)=>piece(p,'box',x,y,z,w,h,d,c);
  function trailing(p,x,y,z,n){const g=group(p,x,y,z,'sparse-vine');for(let i=0;i<n;i++)piece(g,'leaf',Math.sin(i)*.15,-i*.32,0,.24,.21,.12,i%2?'#8baa59':'#5d966a');wind.push(g);}
  function wall(p,x,y,z,w,h,turn=false){const g=group(p,x,y,z,'open-window-wall');if(turn)g.rotation.y=Math.PI/2;
    box(g,-w*.42,h/2,0,w*.16,h,.30,'#c5c5ac');box(g,w*.42,h*.40,0,w*.16,h*.8,.30,'#a5bcae');
    box(g,0,.28,0,w,.55,.32,'#9fb7aa');box(g,-w*.08,h-.2,0,w*.84,.35,.35,'#e1d4b4');return g;}
  const towers=[];
  // Keep the central shipping lane empty; different heights and broken roof lines form depth.
  const specs=[[-19,-51,6.4,5.0,4.4,0],[31,-22,5.8,5.2,5.4,1],[39,12,5.2,4.8,3.4,2],[-40,21,5.2,4.4,3.0,3],[20,43,5.5,4.5,2.5,1]];
  specs.forEach(([x,z,w,d,top,type],n)=>{
    const g=group(root,x,0,z,`peripheral-ruin-${type}`);g.rotation.y=(n%2?1:-1)*.12;towers.push(g);
    for(let row=0;row<9;row++){
      const y=top-row*3.0;
      box(g,0,y,0,w,.28,d,row?'#83b2ad':'#d1d2b5');
      for(const a of [-1,1])for(const b of [-1,1])box(g,a*(w/2-.18),y-1.45,b*(d/2-.18),.34,2.85,.34,'#83ada9');
      box(g,0,y-2.45,-d/2+.18,w,.8,.26,'#6b9ba0');
      box(g,0,y-2.45,d/2-.16,w,.72,.27,'#83b4af');
      box(g,0,y-.45,d/2-.16,w,.36,.28,'#9bbfb3');
      for(let k=0;k<4;k++)box(g,-w*.44+k*w*.293,y-1.4,d/2-.16,.32,1.55,.3,'#94bbb0');
      box(g,-w/2+.16,y-2.45,0,.27,.72,d,'#78aaa8');
      box(g,-w/2+.16,y-.45,0,.28,.36,d,'#91b9ad');
      box(g,-w/2+.16,y-1.4,0,.28,1.55,.38,'#80aea7');
      if(row>0){for(let k=0;k<3;k++)box(g,-w*.32+k*w*.32,y-1.30,-d/2+.10,.9,1.3,.08,'#356b7f');box(g,-w/2+.14,y-2.45,0,.28,.8,d,'#669da2');}
    }
    wall(g,-w*.48,top+.12,0,d,2.8,true);wall(g,0,top+.12,-d*.47,w,3.2);
    if(type===0){wall(g,w*.46,top+.12,-.9,d*.55,2.1,true);box(g,-1,top+3.3,-1,w*.65,.18,d*.55,'#c8c8a9');}
    if(type===1){box(g,w*.25,top+.16,d*.65,w*.65,.22,1.5,'#b8c2a9');for(let i=0;i<4;i++)box(g,-w*.1+i*.7,top+.8,d*.86,.12,1.2,.12,'#d8cfaf');box(g,w*.24,top+1.45,d*.86,w*.7,.13,.15,'#e0d4ae');}
    if(type===2){for(let i=0;i<4;i++){const slab=box(g,-w*.3+i*.7,top+.2,0,.65,.18,d*.7,'#9db4a5');slab.rotation.z=i*.045;}}
    if(type===3){for(let i=0;i<8;i++)box(g,w*.25,top+.15-i*.30,d*.35+i*.32,1.1,.22,.43,'#b2c5b1');}
    for(let k=0;k<4;k++){const rubble=box(g,-w*.3+k*.8,top+.24,d*.25,.45,.26,.4,'#b4bba3');rubble.rotation.y=k*.7;}
    trailing(g,-w*.48,top+.35,d*.2,5+n);trailing(g,w*.18,top+3.3,-d*.45,4);
    for(let k=0;k<4;k++)piece(g,'leaf',-w*.32+k*.25,top+.35,d*.2,.25,.28,.3,k%2?'#99b664':'#6d9a63');
  });
  const shallows=[];
  // These are submerged roofs, not opaque colour planes. Open bays stay visible below each roof.
  const shelves=[[-6,-11,-1.0,5.0,4.2],[13,7,-1.55,4.5,4.6],[-8,22,-2.1,4.4,3.8],[19,-4,-3.1,4.0,3.8]];
  shelves.forEach(([x,z,y,w,d],i)=>{
    const g=group(root,x,y,z,`submerged-roof-${i}`);g.rotation.y=-.12+i*.14;shallows.push(g);
    box(g,0,0,0,w,.28,d,'#77b5aa');
    // Separated light paving patches let refraction expose edges and a readable terrace plan.
    for(let a=0;a<3;a++)for(let b=0;b<2;b++)box(g,-w*.30+a*w*.3,.16,-d*.25+b*d*.5,w*.27,.045,d*.44,(a+b)%2?'#a3c6ad':'#89bba9');
    for(const yy of [-2.8,-5.6,-8.4,-11.2,-14.0,-16.8]){
      box(g,0,yy,0,w,.22,d,'#6eaaa6');
      for(const a of [-1,1])for(const b of [-1,1])box(g,a*(w/2-.16),yy+1.35,b*(d/2-.16),.3,2.7,.3,'#60999f');
      box(g,0,yy+.5,-d*.48,w,.7,.23,'#417e8c');
      for(let c=0;c<3;c++)box(g,-w*.32+c*w*.32,yy+1.6,-d*.48,.85,1.25,.10,'#366d80');
    }
    wall(g,-w*.46,.12,-.1,d*.75,.75,true);
    for(let step=0;step<7;step++)box(g,w*.30,-step*.33,d*.43+step*.32,1.1,.22,.43,'#87b5a9');
    box(g,w*.20,-2.25,d*.43+2.0,2.7,.25,2.4,'#68a7a2');
    for(let k=0;k<4;k++){const m=box(g,-w*.3+k*.7,.27,.5,.38,.2,.30,'#9fbca6');m.rotation.y=k*.8;}
    trailing(g,-w*.4,-.05,d*.4,6);
  });
  // Reference landmarks are full independent buildings, distinct from the small ruin variants.
  const landmarks=[];
  function planter(p,x,y,z,w=1.4){
    box(p,x,y+.2,z,w,.4,.75,'#cfad7c');box(p,x,y+.42,z,w*.88,.06,.61,'#77563e');
    for(let i=0;i<5;i++){const xx=x-w*.35+i*w*.175;piece(p,'leaf',xx,y+.65,z,.35,.38,.38,i%2?'#99be51':'#5a9c56');
      if(i%2)for(let j=0;j<4;j++)piece(p,'leaf',xx+Math.sin(j*1.57)*.14,y+.96,z+Math.cos(j*1.57)*.14,.16,.09,.16,'#ed9ab7');}
  }
  const round=group(root,-54,0,12,'reference-round-garden-building');landmarks.push(round);
  // Continuous rounded shell with readable inset bays, not a column with decorations.
  for(let floor=0;floor<9;floor++){
    const y=7.6-floor*2.8;
    piece(round,'cyl',0,y,0,5.5,.32,4.7,'#d2d9bd');
    piece(round,'cyl',0,y-1.4,0,5.15,2.55,4.35,floor?'#88b4b0':'#b5cbbd');
    for(let k=0;k<20;k++){const a=k*Math.PI/10;const bay=group(round,Math.cos(a)*5.25,y-1.4,Math.sin(a)*4.48,'recessed-curved-window');bay.rotation.y=-a+Math.PI/2;
      box(bay,0,0,0,1.15,1.8,.12,'#397787');box(bay,-.70,0,.06,.18,2.55,.24,'#d0d5b8');box(bay,0,0,.09,.06,1.8,.10,'#a4c4bc');}
  }
  piece(round,'cyl',0,7.83,0,5.18,.16,4.38,'#d9c99e');
  for(let i=0;i<18;i++){const a=i*Math.PI/9;const rail=group(round,Math.cos(a)*5.25,8.35,Math.sin(a)*4.45);rail.rotation.y=-a+Math.PI/2;box(rail,0,0,0,.14,.9,.14,'#e9dfbe');box(rail,0,.47,0,1.85,.13,.18,'#e9dfbe');}
  for(const [x,z] of [[-3,1.8],[2.8,1.7],[-2.8,-2.5],[2.8,-2.5]])planter(round,x,7.95,z,2);
  piece(round,'cyl',-1.6,9.0,-.9,.22,2.2,.22,'#aa8051');
  for(let i=0;i<7;i++)piece(round,'leaf',-1.6+Math.sin(i*2.4)*.9,10.2+(i%3)*.4,-.9+Math.cos(i*2.4)*.8,1.25,.95,1.15,i%2?'#a8c958':'#77ad51');
  piece(round,'cyl',2.2,9,0,.06,2.4,.06,'#b28b53');piece(round,'cone',2.2,10.25,0,1.65,.6,1.65,'#f1d9ad');
  for(const x of [1.3,3.0]){box(round,x,8.3,.8,.65,.15,1.25,'#d8b782');box(round,x,8.7,.28,.65,.7,.13,'#eee0ba');}
  for(let k=0;k<12;k++){const a=k*Math.PI/6;trailing(round,Math.cos(a)*5.42,8,Math.sin(a)*4.65,12+k%6);}
  const residence=group(root,-30,0,40,'reference-balcony-residence');landmarks.push(residence);
  for(let f=0;f<10;f++){
    const y=10-f*2.8;
    box(residence,0,y-1.4,0,7,2.8,5.8,f<3?'#d8dac2':'#82b1ad');box(residence,0,y,0,7.4,.22,6.2,'#e0d8b9');
    for(const x of [-2.25,0,2.25]){box(residence,x,y-1.35,2.94,1.15,1.8,.08,'#438492');box(residence,x,y-1.35,3.03,.075,1.85,.08,'#d3b27c');
      for(const side of [-1,1])box(residence,x+side*.75,y-1.35,3.03,.25,1.85,.12,'#74aaa9');}
    for(const z of [-1.8,1.8]){box(residence,-3.54,y-1.35,z,.09,1.8,1.2,'#3b7985');box(residence,-3.63,y-1.35,z,.09,1.8,.08,'#d3b27c');}
    if(f<3){const x=f%2?-2:1.4;box(residence,x,y-2.65,3.65,3.3,.2,1.5,'#c59c68');
      for(let k=0;k<5;k++)box(residence,x-1.5+k*.75,y-2.1,4.3,.12,1,.12,'#b7ad83');box(residence,x,y-1.56,4.3,3.3,.13,.15,'#ddd0a9');planter(residence,x,y-2.55,3.5,2.3);}
  }
  box(residence,-1.2,11.15,-1,3.5,2.1,3.0,'#e8d9b6');box(residence,-1.2,12.3,-1,3.9,.25,3.4,'#c6b68b');box(residence,-1.2,11.1,.54,1.0,1.6,.1,'#58949b');
  for(const x of [-2.8,0,2.8]){planter(residence,x,10.12,2.3,2);trailing(residence,x,10.3,3.12,20);}
  const low=group(root,12,-1.3,29,'reference-submerged-courtyard');landmarks.push(low);
  for(let f=0;f<7;f++){const y=-f*2.8;box(low,0,y,0,7.2,.25,6.4,'#91bab0');
    for(const x of [-3.2,3.2])for(const z of [-2.8,2.8])box(low,x,y-1.4,z,.45,2.8,.45,'#699e9e');
    box(low,0,y-1.3,-3,7,.6,.25,'#5b9199');}
  wall(low,-3.3,.1,0,5.8,.8,true);wall(low,0,.1,-2.9,6.8,.75);
  box(low,-.9,.15,-.6,1.5,.12,1.2,'#406f80');for(const x of [-1.65,-.15])box(low,x,.23,-.6,.12,.18,1.4,'#b3c7b5');
  for(let k=0;k<8;k++)box(low,2,-k*.3,3+k*.32,1.4,.25,.45,'#9cbfb0');
  for(let k=0;k<5;k++)trailing(low,-3+k*1.4,.3,2.9,5);
  // Batch a whole building, while keeping each moving vine independent.
  const moving=new Set(wind);
  for(const anchor of [...towers,...shallows,...landmarks,...wind]){
    anchor.updateWorldMatrix(true,true);const inverse=anchor.matrixWorld.clone().invert(),buckets=new Map();
    function collect(node){
      if(node!==anchor&&moving.has(node))return;
      if(node.isMesh){const key=node.geometry.uuid+node.material.uuid;if(!buckets.has(key))buckets.set(key,[]);buckets.get(key).push(node);}
      for(const child of node.children)collect(child);
    }
    collect(anchor);
    for(const list of buckets.values())if(list.length>1){const inst=new T.InstancedMesh(list[0].geometry,list[0].material,list.length);
      list.forEach((m,i)=>{inst.setMatrixAt(i,new T.Matrix4().multiplyMatrices(inverse,m.matrixWorld));m.parent.remove(m);});
      inst.castShadow=true;inst.receiveShadow=true;inst.computeBoundingSphere();anchor.add(inst);}
  }
  return {root,towers,shallows,landmarks,update(t){wind.forEach((g,i)=>{g.rotation.z=Math.sin(t*.65+i)*.035;});}};
}
