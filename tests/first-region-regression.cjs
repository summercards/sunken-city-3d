// Physical enclosure, connected northern descent, and real rendered art checks.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-gl=angle','--use-angle=metal','--enable-webgl','--ignore-gpu-blocklist']});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await page.route('**/index.html',async route=>{const response=await route.fetch();let body=await response.text();body=body.replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,renderer,scene,firstRegion,waterSystem};\n    const clock = new THREE.Clock();');body=body.replace('      diving.update(dt, t);','      if(!window.freezeDive) diving.update(dt, t);');await route.fulfill({response,body});});
  await page.goto((process.env.APP_URL||'http://127.0.0.1:8765')+'/index.html');await page.waitForFunction(()=>window.qa,null,{timeout:60000});
  const surface=await page.evaluate(()=>{
   const {gameplay:g,firstRegion:r,THREE:T}=qa;g.probe.refreshBlockers();
   const home=g.zones.get('zone1').boatPark;
   const routes=g.zones.list.slice(1).map(z=>({id:z.id,path:g.probe.sailPath({x:home.x,z:home.z},{x:z.boatPark.x,z:z.boatPark.z})}));
   const walls=r.walls.map(w=>{const p=w.getWorldPosition(new T.Vector3());return !g.probe.hullClear(p.x,p.z,0)});
   const exitRemoved=!r.root.getObjectByName('northeast-suspension-bridge')&&!r.root.getObjectByName('northeast-closed-water-gate');
   const exitClear=[-90,-110,-140].every(z=>g.probe.hullClear(49.56*1.3,z,0));
   const points=[[-36,-12,Math.PI/2,-.10,0],[-19,34,0,0,.10]];
   const contacts=points.map(([x,z,yaw,dx,dz])=>{[x,z]=r.boundaryPoint([x,z]);const from=[x,z];let pushes=0;const initiallyClear=g.probe.hullClear(x,z,yaw);for(let i=0;i<400;i++){const p=g.probe.boatResolve(x+dx,z+dz,yaw);x=p.x;z=p.z;pushes+=p.pushed;}return {from,initiallyClear,resolved:{x,z,pushes},clearAfterBackingOff20cm:g.probe.hullClear(x-dx*2,z-dz*2,yaw)}});
   routes.push({id:'expanded-west-water',path:g.probe.sailPath({x:home.x,z:home.z},{x:-82,z:-16})});
   return {routes,walls,exitRemoved,exitClear,contacts,outerCount:r.outerCity.placements.length,outerBatches:r.outerCity.batches,outerColliders:r.outerCity.solids.children.length,count:r.buildings.length,scales:r.buildings.every(g=>g.scale.toArray().every(s=>s===1.2)),leaning:r.buildings.filter(g=>Math.abs(g.rotation.z)>.12).length,calls:qa.renderer.info.render.calls};
  });
  assert(surface.scales&&surface.count>=30&&surface.leaning>=6);
  assert(surface.outerCount>600&&surface.outerBatches<100&&surface.outerColliders===surface.outerCount);
  assert(surface.walls.every(Boolean),'Every wall must participate in real boat collision');
  assert(surface.exitRemoved&&surface.exitClear,'Former exit segment must be removed and free of invisible blockers');
  for(const r of surface.routes)assert(r.path&&r.path.length>=2,`${r.id} remains accessible inside the region`);
  for(const c of surface.contacts)assert(c.initiallyClear&&c.clearAfterBackingOff20cm&&c.resolved.pushes>6,'A moving hull must stop against the boundary');
  await page.click('#dive-button');await page.waitForFunction(()=>qa.diving.phase==='swim');
  await page.evaluate(()=>{window.freezeDive=true;qa.gameplay.art.explorerGroup.position.set(0,-71,-23)});
  await page.keyboard.down('KeyW');await page.keyboard.down('KeyQ');
  const crossing=await page.evaluate(()=>{for(let i=0;i<220;i++)qa.diving.update(.05,10+i*.05);return qa.gameplay.art.explorerGroup.position.toArray()});
  await page.keyboard.up('KeyW');await page.keyboard.up('KeyQ');
  assert(crossing[2]<-43&&crossing[1]<-75,`Northern passage must open beyond both old clamps: ${crossing}`);
  const terrain=await page.evaluate(()=>{
   const {THREE:T,diving:{art:a}}=qa,ray=new T.Raycaster(new T.Vector3(0,-60,-100),new T.Vector3(0,-1,0));
   qa.scene.updateMatrixWorld(true);
   const hits=ray.intersectObject(a.trench.ground,false);
   const path=[];
   // Trace a continuous, body-clear water corridor above the connected heightfield.
   for(let z=-26;z>=-165;z-=.5){const s=a.trench.sectionAt(z),y=s.floor+30;const p=new T.Vector3(s.center,y,z);path.push(a.insideBasin(p,1.35)&&!a.solidBuildings.some(b=>y<b.top+.5&&y>b.bottom&&Math.abs(p.x-b.x)<b.w+.35&&Math.abs(p.z-b.z)<b.d+.35));}
   return {finite:Array.from(a.trench.ground.geometry.attributes.position.array).every(Number.isFinite),floor:a.trench.floorAt(0,-132),hit:hits[0]?.point.y,predicted:a.trench.floorAt(0,-100),pathClear:path.every(Boolean),outside:a.insideBasin(new T.Vector3(0,-240,-132),1),ship:a.trench.ship.userData,coralTypes:[...new Set(a.trench.corals.map(c=>c.userData.type))]};
  });
  assert(terrain.finite&&terrain.floor===-225&&!terrain.outside);
  assert(Math.abs(terrain.hit-terrain.predicted)<.3&&terrain.hit<-150,'Visible seabed must agree with swim collision and have no old flat floor');
  assert(terrain.pathClear,'A continuous centreline above the seabed must connect the old basin to the new trench');
  assert(terrain.coralTypes.length===3&&terrain.ship.length>=30);
  await page.evaluate(()=>{qa.gameplay.art.explorerGroup.position.set(0,-213,-151);for(let i=0;i<20;i++)qa.diving.update(.05,30+i*.05)});
  await page.keyboard.down('KeyQ');
  const deep=await page.evaluate(()=>{for(let i=0;i<160;i++)qa.diving.update(.05,40+i*.05);const p=qa.gameplay.art.explorerGroup.position;return {p:p.toArray(),inside:qa.diving.art.insideBasin(p,1.3),floor:qa.diving.art.trench.floorAt(p.x,p.z),hud:document.getElementById('dive-depth').textContent}});
  await page.keyboard.up('KeyQ');
  assert(deep.p[1]<-220&&deep.p[1]>deep.floor+1&&deep.inside,JSON.stringify(deep));
  assert(deep.hud.includes('北境沉船海沟'));
  await page.evaluate(()=>{window.freezeDive=false;qa.diving.exit()});await page.waitForFunction(()=>qa.diving.phase==='surface');
  assert(await page.evaluate(()=>qa.firstRegion.root.visible&&qa.waterSystem.surface.visible),'Returning restores surface scenery');
  assert.deepEqual(errors,[]);
  const report={passed:true,surface,terrain,crossing,deep,errors};
  fs.mkdirSync('outputs/first-region',{recursive:true});fs.writeFileSync('outputs/first-region/regression.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify({passed:true,buildings:surface.count,blockingWalls:surface.walls.length,exitRemoved:surface.exitRemoved,exitClear:surface.exitClear,reachableZones:surface.routes.map(r=>r.id),crossing,deep,errors},null,2));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
