import { createUnderwaterArt } from './underwater-art.js';

export function createDiving({ THREE:T,scene,worldGroup,camera,controls,renderer,waterSystem,globalUniforms,
  explorerGroup:diver,swimParts,state,economy,syncUI,waterLevel }) {
  const $=id=>document.getElementById(id),button=$('dive-button'),hud=$('dive-hud'),pad=$('dive-controls'),progress=$('dive-progress');
  const art=createUnderwaterArt({THREE:T,scene,worldGroup,waterLevel});
  const keys=new Set(),done=new Set(),chests=[],tags=[];
  
  let phase='surface',elapsed=0,aiming=false,origin=null,search=null,yaw=0,distance=10,pitch=1.21,drag=null,exitY=0,swimRoute=null;
  const fromCamera=new T.Vector3(),fromTarget=new T.Vector3(),entry=new T.Vector3(),velocity=new T.Vector3();
  const body=swimParts.explorerBodyPivot;
  const gear=new T.Group();gear.name='diving-equipment';gear.visible=false;body.add(gear);
  art.box(gear,'#183e4b',0,.98,.20,.42,.18,.12);
  art.box(gear,'#a9e1d8',0,1,.27,.32,.12,.04);
  art.rock(gear,'#e8bb60',0,.5,-.23,.2,.4,.17);
  const fins=[-1,1].map((s,i)=>{const pivot=i?swimParts.rightLegPivot:swimParts.leftLegPivot;const f=art.box(pivot,'#eabf5c',0,-.3,.22,.22,.075,.48);f.visible=false;return f;});
  const specs=[[-6,-17.55,2,'珊瑚花园宝箱',{parts:2,wood:2}],[6.5,-30.55,-7,'蓝礁遗藏',{coins:12,pearl:1}],[-5.5,-45.55,-20,'旧城工具箱',{parts:3,wood:2}],[6.5,-58.55,12,'紫珊瑚珍藏',{pearl:2,fish:2}],[0,-73.55,-27,'深谷补给箱',{wood:4,coins:20}]];
  specs.forEach(([x,y,z,name,reward],id)=>{
    const g=new T.Group();g.position.set(x,y,z);g.name=name;art.root.add(g);
    art.box(g,'#624a34',0,.4,0,1.35,.75,.85);
    for(const s of [-1,1])art.box(g,'#d9b962',s*.45,.42,0,.1,.8,.9);
    const lid=new T.Group();lid.position.set(0,.79,-.43);g.add(lid);art.box(lid,'#94714b',0,.12,.43,1.42,.25,.92);
    for(const s of [-1,1])art.box(lid,'#dfbf6b',s*.45,.14,.43,.11,.28,.94);
    art.box(g,'#f2d887',0,.55,.46,.18,.23,.08);
    const tag=document.createElement('button');tag.className='dive-treasure';tag.hidden=true;tag.type='button';tag.setAttribute('aria-label',`搜索${name}`);document.body.appendChild(tag);
    const c={g,lid,name,reward,id,opening:0,tag};tag.onclick=()=>visitChest(c);chests.push(c);tags.push(tag);
  });
  const bubbleGeo=new T.SphereGeometry(1,7,5),bubbleMat=new T.MeshStandardMaterial({color:'#c6ede5',metalness:.25,roughness:.12,transparent:true,opacity:.38,depthWrite:false});
  const bubbles=Array.from({length:20},(_,i)=>{const g=new T.Mesh(bubbleGeo,bubbleMat);g.visible=false;art.root.add(g);return {g,life:-i*.15};});
  function notify(text){const tip=$('dive-found');tip.textContent=text;tip.classList.add('show');clearTimeout(notify.timer);notify.timer=setTimeout(()=>tip.classList.remove('show'),2600);}
  function sync(){
    button.textContent=phase==='swim'?'返回海面':phase==='enter'?'正在下潜…':phase==='exit'?'正在上浮…':aiming?'取消选点':'潜水';
    button.disabled=['enter','exit'].includes(phase)||(phase==='surface'&&!['IDLE_ASHORE','BOAT_IDLE'].includes(state.workerMode));
    $('dive-aim-hint').hidden=!aiming;pad.hidden=phase==='surface';hud.classList.toggle('diving',phase!=='surface');hud.classList.toggle('aiming',aiming);
    $('dive-depth').textContent=`深度 ${(Math.max(0,waterLevel-diver.position.y)).toFixed(1)} m`;
  }
  function blocked(p,margin=.35){
    if(!art.insideBasin(p,margin+1))return true;
    if(art.solidBuildings.some(b=>p.y<b.top+.5&&p.y>b.bottom&&Math.abs(p.x-b.x)<b.w+margin&&Math.abs(p.z-b.z)<b.d+margin))return true;
    return art.terraces.some(([x,z,w,d,y])=>p.y<y+.85&&p.y> -76&&Math.pow((p.x-x)/(w*.85+margin),2)+Math.pow((p.z-z)/(d*.8+margin),2)<1);
  }
  function setImmersed(on){
    waterSystem.surface.visible=!on;globalUniforms.uUnderwaterView.value=on?1:0;
    document.body.classList.toggle('underwater-view',on);art.root.visible=on;
    if(on){
      origin.visibility.forEach(([o])=>o.visible=false);
      scene.fog=new T.FogExp2('#26bec8',.032);scene.background=new T.Color('#26bec8');camera.fov=55;camera.near=.12;
      origin.lights.forEach(({light})=>light.intensity=0);
    }else{
      origin.visibility.forEach(([o,visible])=>o.visible=visible);
      scene.fog=origin.fog;scene.background=origin.background;camera.fov=origin.fov;camera.near=origin.near;origin.lights.forEach(({light,intensity})=>light.intensity=intensity);
    }
    camera.updateProjectionMatrix();
  }
  function start(point){
    if(phase!=='surface'||!['IDLE_ASHORE','BOAT_IDLE'].includes(state.workerMode))return false;
    if(Math.abs(point.x)>65||Math.abs(point.z)>65){notify('请选择建筑之间开阔的水面');return false;}
    origin={parent:diver.parent,pos:diver.position.clone(),rot:diver.rotation.clone(),scale:diver.scale.clone(),bodyRot:body.rotation.clone(),bodyPos:body.position.clone(),
      camera:camera.position.clone(),target:controls.target.clone(),mode:state.workerMode,manual:state.manualCamera,lock:state.camLockMode,
      fog:scene.fog,background:scene.background,fov:camera.fov,near:camera.near,enabled:controls.enabled,visibility:scene.children.filter(o=>o!==art.root&&o!==diver&&!o.isLight).map(o=>[o,o.visible]),lights:scene.children.filter(o=>o.isLight).map(light=>({light,intensity:light.intensity}))};
    scene.attach(diver);entry.set(0,waterLevel,12);diver.position.copy(entry);diver.scale.setScalar(1.25);diver.rotation.set(0,Math.PI,0);
    fromCamera.set(0,8,30);fromTarget.set(0,-6,8);phase='enter';elapsed=0;aiming=false;yaw=0;pitch=1.21;velocity.set(0,0,0);keys.clear();
    state.workerMode='DIVING';state.manualCamera=true;controls.enabled=false;gear.visible=true;[swimParts.hatBrim,swimParts.hatCrown,swimParts.toolGroup].forEach(o=>{if(o){o.userData.beforeDiveVisible=o.visible;o.visible=false;}});fins.forEach(f=>f.visible=true);
    setImmersed(true);sync();return true;
  }
  function exit(){if(phase!=='swim')return;phase='exit';elapsed=0;exitY=diver.position.y;search=null;swimRoute=null;keys.clear();progress.hidden=true;tags.forEach(t=>t.hidden=true);fromCamera.copy(camera.position);fromTarget.copy(controls.target);sync();}
  function finish(){
    setImmersed(false);origin.parent.add(diver);diver.position.copy(origin.pos);diver.rotation.copy(origin.rot);diver.scale.copy(origin.scale);body.rotation.copy(origin.bodyRot);body.position.copy(origin.bodyPos);
    for(const p of [swimParts.leftArmPivot,swimParts.rightArmPivot,swimParts.leftLegPivot,swimParts.rightLegPivot])p.rotation.x=0;
    camera.position.copy(origin.camera);controls.target.copy(origin.target);controls.enabled=origin.enabled;
    state.workerMode=origin.mode;state.manualCamera=origin.manual;state.camLockMode=origin.lock;phase='surface';gear.visible=false;[swimParts.hatBrim,swimParts.hatCrown,swimParts.toolGroup].forEach(o=>{if(o)o.visible=o.userData.beforeDiveVisible;});fins.forEach(f=>f.visible=false);sync();
  }
  function clearSegment(a,b){
    const steps=Math.max(1,Math.ceil(a.distanceTo(b)/.6)),sample=new T.Vector3();
    for(let i=1;i<=steps;i++)if(blocked(sample.lerpVectors(a,b,i/steps)))return false;
    return true;
  }
  function planSwim(destination){
    const start=diver.position.clone();if(clearSegment(start,destination))return [destination];
    // Small 3D navigation grid routes above or around reef shelves instead of swimming through them.
    const step=2.5,key=(x,y,z)=>`${x},${y},${z}`,open=[],visited=new Map();
    const first={x:0,y:0,z:0,p:start,g:0,f:start.distanceTo(destination),parent:null};open.push(first);visited.set('0,0,0',first);
    const directions=[[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
    let finish=null;
    for(let n=0;open.length&&n<4500;n++){
      open.sort((a,b)=>b.f-a.f);const node=open.pop();if(node.closed)continue;node.closed=true;
      if(node.p.distanceTo(destination)<step*1.8&&clearSegment(node.p,destination)){finish=node;break;}
      for(const [dx,dy,dz] of directions){
        const x=node.x+dx,y=node.y+dy,z=node.z+dz,k=key(x,y,z),p=start.clone().add(new T.Vector3(x,y,z).multiplyScalar(step));
        if(!art.insideBasin(p,1)||p.y< -74.5||p.y> -4.8||!clearSegment(node.p,p))continue;
        const g=node.g+step,old=visited.get(k);if(old&&old.g<=g)continue;
        const next={x,y,z,p,g,f:g+p.distanceTo(destination),parent:node};visited.set(k,next);open.push(next);
      }
    }
    if(!finish)return null;
    const path=[destination];for(let n=finish;n.parent;n=n.parent)path.unshift(n.p);
    const smooth=[];let anchor=start,index=0;
    while(index<path.length){let last=index;for(let j=index+1;j<path.length;j++){if(!clearSegment(anchor,path[j]))break;last=j;}smooth.push(path[last]);anchor=path[last];index=last+1;}
    return smooth;
  }
  function visitChest(c){
    if(phase!=='swim'||done.has(c.id)||search?.c===c)return;
    search=null;progress.hidden=true;
    const destination=c.g.position.clone().add(new T.Vector3(c.g.position.x<0?1.6:c.g.position.x>0?-1.6:0,1.45,1.1));
    if(diver.position.distanceTo(c.g.position)<3.4){beginSearch(c);return;}
    const points=planSwim(destination);if(!points){notify('前方礁石较密，请先游到开阔水域');return;}swimRoute={c,points};
    notify('正在游向'+c.name+' · 方向键可取消');
  }
  function beginSearch(c){
    if(phase!=='swim'||done.has(c.id))return;
    if(diver.position.distanceTo(c.g.position)>3.4){notify('游近宝箱后搜索 · 距离 3 米内');return;}
    search={c,t:0};progress.hidden=false;progress.querySelector('.dive-progress-title').textContent=c.name;progress.style.setProperty('--progress','0%');
  }
  button.addEventListener('click',()=>{if(phase==='swim')exit();else if(phase==='surface'){aiming=!aiming;sync();}});
  const codes=['KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space','KeyQ','KeyE'];
  window.addEventListener('keydown',e=>{if(phase==='swim'){if(e.code==='Escape')exit();if(codes.includes(e.code)){e.preventDefault();keys.add(e.code);}}else if(e.code==='Escape'&&aiming){aiming=false;sync();}});
  window.addEventListener('keyup',e=>keys.delete(e.code));
  window.addEventListener('blur',()=>{keys.clear();drag=null;});
  for(const [id,key] of [['forward','KeyW'],['back','KeyS'],['left','KeyA'],['right','KeyD'],['up','KeyE'],['down','KeyQ']]){
    const b=$(`dive-${id}`);b.style.touchAction='none';b.onpointerdown=e=>{e.preventDefault();b.setPointerCapture(e.pointerId);keys.add(key);};
    for(const event of ['pointerup','pointercancel','lostpointercapture'])b.addEventListener(event,()=>keys.delete(key));
  }
  const canvas=renderer.domElement,ray=new T.Raycaster(),pointer=new T.Vector2();
  function rayAt(e){const r=canvas.getBoundingClientRect();pointer.set((e.clientX-r.left)/r.width*2-1,1-(e.clientY-r.top)/r.height*2);ray.setFromCamera(pointer,camera);}
  canvas.addEventListener('contextmenu',e=>{if(phase!=='surface')e.preventDefault();});
  canvas.addEventListener('pointerdown',e=>{if(phase==='swim'&&e.button===2){drag={x:e.clientX,y:e.clientY};canvas.setPointerCapture(e.pointerId);}},true);
  canvas.addEventListener('pointermove',e=>{if(drag){yaw-=(e.clientX-drag.x)*.005;pitch=T.MathUtils.clamp(pitch+(e.clientY-drag.y)*.008,-1.15,1.6);drag.x=e.clientX;drag.y=e.clientY;}},true);
  canvas.addEventListener('pointercancel',()=>{drag=null;});
  canvas.addEventListener('wheel',e=>{if(phase==='swim'){e.preventDefault();distance=T.MathUtils.clamp(distance+e.deltaY*.008,5,11);}}, {passive:false,capture:true});
  canvas.addEventListener('pointerup',e=>{
    drag=null;if(!aiming&&phase==='surface')return;e.stopImmediatePropagation();if(e.button!==0)return;rayAt(e);
    if(aiming){
      const point=ray.ray.intersectPlane(new T.Plane(new T.Vector3(0,1,0),-waterLevel),new T.Vector3());
      if(point){const distance=ray.ray.origin.distanceTo(point);const land=ray.intersectObjects(worldGroup.children,true).some(h=>{if(h.distance>=distance-.1||h.point.y<waterLevel+.1)return false;for(let o=h.object;o;o=o.parent)if(!o.visible)return false;return true;});
        if(land)notify('请点选建筑之间的海面');else start(point);}
      return;
    }
    if(phase!=='swim')return;
    const hits=ray.intersectObjects(chests.filter(c=>!done.has(c.id)).map(c=>c.g),true);if(hits.length){let obj=hits[0].object;while(obj&&obj.parent!==art.root)obj=obj.parent;const c=chests.find(c=>c.g===obj);if(c)visitChest(c);}
  },true);
  const projected=new T.Vector3();
  function update(dt,t){
    dt=Math.min(dt,.05);if(phase==='surface'){sync();return;}elapsed+=dt;
    const blend=T.MathUtils.smootherstep(Math.min(elapsed/2.2,1),0,1);
    if(phase==='enter') {diver.position.y=T.MathUtils.lerp(waterLevel,-10,blend);if(blend===1){phase='swim';elapsed=0;}}
    else if(phase==='exit'){diver.position.y=T.MathUtils.lerp(exitY,waterLevel,blend);if(blend===1){finish();return;}}
    if(phase==='swim'){
      const axis=(a,b,c,d)=>(keys.has(a)||keys.has(b)?1:0)-(keys.has(c)||keys.has(d)?1:0);
      const x=axis('KeyD','ArrowRight','KeyA','ArrowLeft'),z=axis('KeyS','ArrowDown','KeyW','ArrowUp'),y=axis('KeyE','Space','KeyQ','KeyQ');
      let desired=new T.Vector3(x,y*.7,z);if(desired.length()>1)desired.normalize();desired.applyAxisAngle(new T.Vector3(0,1,0),yaw).multiplyScalar(3.8);
      if(x||y||z)swimRoute=null;
      if(swimRoute){
        const delta=swimRoute.points[0].clone().sub(diver.position),length=delta.length();
        if(length<.25){swimRoute.points.shift();if(!swimRoute.points.length){const c=swimRoute.c;swimRoute=null;beginSearch(c);}}
        else desired=delta.normalize().multiplyScalar(Math.min(4.5,length*3));
      }
      velocity.lerp(desired,1-Math.exp(-dt*7));const next=diver.position.clone().addScaledVector(velocity,dt);
      next.y=T.MathUtils.clamp(next.y,-74.5,-4.8);next.x=T.MathUtils.clamp(next.x,-26,26);next.z=T.MathUtils.clamp(next.z,-42,42);
      if(!blocked(next))diver.position.copy(next);else{
        // Resolve per axis so skimming a ledge slides naturally, while descent cannot pass through it.
        for(const axis of ['y','x','z']){const probe=diver.position.clone();probe[axis]=next[axis];if(!blocked(probe))diver.position[axis]=probe[axis];else velocity[axis]=0;}
      }
      if(Math.hypot(velocity.x,velocity.z)>.15){const a=Math.atan2(velocity.x,velocity.z);diver.rotation.y+=Math.atan2(Math.sin(a-diver.rotation.y),Math.cos(a-diver.rotation.y))*Math.min(1,dt*7);}
      body.rotation.x=.25+Math.min(velocity.length()*.08,.3);body.position.y=Math.sin(t*1.8)*.035;
      swimParts.leftArmPivot.rotation.x=Math.sin(t*3.3)*.7-.4;swimParts.rightArmPivot.rotation.x=-Math.sin(t*3.3)*.7-.4;
      swimParts.leftLegPivot.rotation.x=Math.sin(t*4.5)*.45;swimParts.rightLegPivot.rotation.x=-Math.sin(t*4.5)*.45;
      if(search){
        if(diver.position.distanceTo(search.c.g.position)>3.4){search=null;progress.hidden=true;}
        else{search.t+=dt;progress.style.setProperty('--progress',`${Math.min(1,search.t/3)*100}%`);
          if(search.t>=3){const c=search.c;search=null;progress.hidden=true;if(economy.receive(c.reward)){done.add(c.id);c.opening=1;c.tag.hidden=true;syncUI();notify(`找到物资 · ${Object.entries(c.reward).map(([k,v])=>`${({wood:'木料',parts:'旧零件',pearl:'珍珠',coins:'海贝',fish:'鱼'})[k]} ×${v}`).join(' · ')}`);}else notify('背包已满，请先整理物资');}
        }
      }
    }
    const forward=new T.Vector3(-Math.sin(yaw),0,-Math.cos(yaw));
    const target=diver.position.clone().add(new T.Vector3(0,.5,0)).addScaledVector(forward,1.6);
    const cam=diver.position.clone().addScaledVector(forward,-distance).add(new T.Vector3(0,distance*pitch,0));
    cam.y=Math.min(cam.y,waterLevel-.4);
    // Pull in if a camera orbit would put the lens inside a solid city block.
    for(let i=0;i<8&&blocked(cam,.15);i++)cam.lerp(diver.position,.18);
    if(phase==='enter'){camera.position.lerpVectors(fromCamera,cam,blend);controls.target.lerpVectors(fromTarget,target,blend);}
    else if(phase==='exit'){camera.position.lerpVectors(fromCamera,origin.camera,blend);controls.target.lerpVectors(fromTarget,origin.target,blend);}
    else{const ease=1-Math.exp(-dt*6);camera.position.lerp(cam,ease);controls.target.lerp(target,ease);}
    camera.lookAt(controls.target);camera.updateMatrixWorld(true);
    art.update(dt,t,camera,diver);
    bubbles.forEach((b,i)=>{b.life+=dt;if(b.life>3){b.life=0;b.g.position.copy(diver.position).add(new T.Vector3(Math.sin(diver.rotation.y)*.3,1.2,Math.cos(diver.rotation.y)*.3));b.g.visible=true;}
      if(b.life>=0){b.g.position.y+=dt*(.6+i%3*.1);b.g.position.x+=Math.sin(t*2+i)*dt*.07;b.g.scale.setScalar(.035+b.life*.016);}
    });
    chests.forEach(c=>{
      if(done.has(c.id)){c.lid.rotation.x=T.MathUtils.lerp(c.lid.rotation.x,-1.7,1-Math.exp(-dt*3));c.tag.hidden=true;return;}
      projected.copy(c.g.position).add(new T.Vector3(0,1.6,0)).project(camera);
      const d=diver.position.distanceTo(c.g.position);c.tag.hidden=phase!=='swim'||projected.z>1||Math.abs(projected.x)>.94||Math.abs(projected.y)>.83||d>34||Math.abs(diver.position.y-c.g.position.y)>21;
      c.tag.style.left=`${(projected.x*.5+.5)*innerWidth}px`;c.tag.style.top=`${(-projected.y*.5+.5)*innerHeight}px`;
      c.tag.textContent=swimRoute?.c===c?'◇ 正在前往':d<3.4?'◇ 搜索':'◇ '+Math.ceil(d)+' m';c.tag.classList.toggle('near',d<3.4);
    });sync();
  }
  return {start,exit,update,get active(){return phase!=='surface';},get phase(){return phase;},renderRefraction(){if(phase!=='surface')art.optics.render(renderer,camera);},art,chests,get navigating(){return !!swimRoute;}};
}
