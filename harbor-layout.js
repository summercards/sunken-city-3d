// Core islands have breathing room; distant districts remain available when sailing.
export function arrangeHarbor({ THREE:T, worldGroup, gameplay, sceneArt, leftBuildingGroup, poleGroup, makePainterlyMat:mat, WATER_LEVEL:water }) {
  const {buildSites,state,zone3Root}=gameplay.art;
  leftBuildingGroup.position.set(-15,.3,-6);
  zone3Root.visible=false;
  // Carry the animated windmill onto the farm rather than leaving it on the retired roof.
  leftBuildingGroup.add(sceneArt.rotor);sceneArt.rotor.position.set(3.8,6.6,0);
  const farm=buildSites.find(s=>s.id==='rooftop_planter');
  farm.hitRoots=[leftBuildingGroup];farm.hoverAnchor.set(-15,5.2,-6);
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
  const aquaSite={id:'shallow_aquaculture',zone:'zone5',name:'浅水养殖台',hitRoots:[aqua],hoverAnchor:new T.Vector3(16,2.5,15),boatParkPos:new T.Vector3(11,water,12),shoreEdgePos:new T.Vector3(13,1.8,14),buildStandPos:new T.Vector3(15,1.8,15),level:0,maxLevel:1,storedCoins:0,coinsPerCycle:0,stages:[{cost:35,rateAdd:2,desc:'修整浅水池，培育水生作物。',applyVisual(p){plants.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(p-.35-i*.025)*3));m.visible=a>0;m.scale.set(a,.24*a,.7*a);});}}]};
  buildSites.push(aquaSite);
  // Use the existing salvage economy from the physical winch as well.
  const ray=new T.Raycaster(),pointer=new T.Vector2();let down=null;
  const canvas=document.querySelector('canvas');
  canvas.addEventListener('pointerdown',e=>{down={x:e.clientX,y:e.clientY};});
  canvas.addEventListener('pointerup',e=>{if(!down||Math.hypot(e.clientX-down.x,e.clientY-down.y)>5)return;
    pointer.set(e.clientX/innerWidth*2-1,1-e.clientY/innerHeight*2);if(e.button!==0)return;ray.setFromCamera(pointer,gameplay.art.camera);
    const h=ray.intersectObjects([salvage,poleGroup,dock],true)[0];if(!h||state.worldVisible&& !state.worldVisible(h.point))return;
    if(salvage.children.some(root=>root===h.object||root===h.object.parent||root===h.object.parent?.parent))gameplay.performSalvage();
    else gameplay.upgradeShip();
  });
  const repairs=[];
  for(let i=0;i<6;i++){const m=box(leftBuildingGroup,1.6+i*.43,3.85,2.3,.39,.18,1.5,'#dbc396');repairs.push(m);}
  return {salvage,dock,aqua,update(t){
    const progress=farm.level>0?1:state.activeJobSite===farm&&state.workerMode==='BUILDING'?state.jobProgress:0;
    repairs.forEach((m,i)=>{const a=Math.max(0,Math.min(1,(progress-i*.055)*5));m.visible=a>0;m.scale.y=Math.max(.001,a);m.position.y=3.85+(1-a)*.45;});plants.forEach((p,i)=>{p.position.y=1.5+Math.sin(t*1.3+i)*.035;});}};
}

// Character-centered world cells. Binary reveal with a separate, fixed spatial water-fog border.
export function createGridView({THREE:T,scene,getFocus}) {
  const size=128,cell=3,origin=-size*cell/2,data=new Uint8Array(size*size*4),pending=new Map();
  const texture=new T.DataTexture(data,size,size,T.RGBAFormat);texture.minFilter=texture.magFilter=T.NearestFilter;texture.generateMipmaps=false;
  const uniforms={uGridPrepass:{value:false},uGridMask:{value:texture},uGridOrigin:{value:origin},uGridSpan:{value:size*cell},uGridCenter:{value:new T.Vector2()},uGridVoid:{value:scene.background.clone().convertLinearToSRGB()}};
  const vertex='varying vec3 vGridWorld;\n';
  const fragment='varying vec3 vGridWorld; uniform bool uGridPrepass; uniform sampler2D uGridMask; uniform float uGridOrigin; uniform float uGridSpan; uniform vec2 uGridCenter; uniform vec3 uGridVoid;\n';
  // Underwater pixels use their water-surface footprint, never a second vertical guillotine.
  // A fixed spatial border absorbs silhouettes before the clipping plane; cell reveal stays binary.
  const discard=`
    float gridDepth=max(0.0,1.12-vGridWorld.y);
    vec2 gridPoint=vGridWorld.xz+vec2(-0.70710678,0.70710678)*gridDepth;
    vec2 gridUV=(gridPoint-vec2(uGridOrigin))/uGridSpan;
    vec2 edgeQ=abs(gridPoint-uGridCenter)-vec2(20.5);
    float edgeDistance=length(max(edgeQ,0.0))+min(max(edgeQ.x,edgeQ.y),0.0)-2.0;
    float gridInterior=1.0-smoothstep(-3.0,0.0,edgeDistance);
    if(edgeDistance>=0.0 || any(lessThan(gridUV,vec2(0.0)))||any(greaterThanEqual(gridUV,vec2(1.0)))||texture2D(uGridMask,gridUV).r<0.5) discard;
  `;
  const finish=`
    if (!uGridPrepass) {
    float depthHaze=smoothstep(5.0,26.0,gridDepth)*0.88;
    gl_FragColor.rgb=mix(gl_FragColor.rgb,vec3(0.055,0.30,0.44),depthHaze);
    gl_FragColor.rgb=mix(uGridVoid,gl_FragColor.rgb,gridInterior);
    gl_FragColor.a=mix(1.0,gl_FragColor.a,gridInterior);
    }
  `;
  const materials=new WeakSet();
  function patch(){scene.traverse(o=>{for(const m of (Array.isArray(o.material)?o.material:[o.material])){
    if(!m||materials.has(m))continue;materials.add(m);const previous=m.onBeforeCompile;
    m.onBeforeCompile=function(shader,renderer){previous.call(this,shader,renderer);Object.assign(shader.uniforms,uniforms);
      shader.vertexShader=vertex+shader.vertexShader.replace(/void main\s*\(\s*\)\s*\{/,'void main() { vGridWorld=(modelMatrix*vec4(position,1.0)).xyz;');
      shader.fragmentShader=shader.fragmentShader.slice(0,shader.fragmentShader.lastIndexOf('}'))+finish+'}';
      shader.fragmentShader=fragment+shader.fragmentShader.replace(/void main\s*\(\s*\)\s*\{/,'void main() {'+discard);
    };const key=m.customProgramCacheKey.bind(m);m.customProgramCacheKey=()=>key()+'grid-view-v2';m.needsUpdate=true;
  }});}
  patch();
  let first=true,lastX=Infinity,lastZ=Infinity;
  function isVisible(p){const x=Math.floor((p.x-origin)/cell),z=Math.floor((p.z-origin)/cell);return x>=0&&x<size&&z>=0&&z<size&&data[(z*size+x)*4]>0;}
  function update(t){
    const focus=getFocus();
    const cx=Math.floor((focus.x-origin)/cell),cz=Math.floor((focus.z-origin)/cell),radius=7;
    uniforms.uGridCenter.value.set(origin+(cx+.5)*cell,origin+(cz+.5)*cell);
    let dirty=false;
    if(cx!==lastX||cz!==lastZ){
      for(let z=0;z<size;z++)for(let x=0;x<size;x++){
        const id=z*size+x,inside=Math.abs(x-cx)<=radius&&Math.abs(z-cz)<=radius;
        if(!inside){if(data[id*4]){data.fill(0,id*4,id*4+4);dirty=true;}pending.delete(id);}
        else if(!data[id*4]&&!pending.has(id)){
          if(first){data.fill(255,id*4,id*4+4);dirty=true;}
          else pending.set(id,t+.08+(Math.abs(x-cx)+Math.abs(z-cz))*.045);
        }
      }first=false;lastX=cx;lastZ=cz;patch();
    }
    for(const [id,at]of pending)if(t>=at){data.fill(255,id*4,id*4+4);pending.delete(id);dirty=true;}
    if(dirty)texture.needsUpdate=true;
  }
  return {update,isVisible,texture,pending,cell,center:uniforms.uGridCenter.value,setUnderwaterPass(value){uniforms.uGridPrepass.value=value;}};
}
