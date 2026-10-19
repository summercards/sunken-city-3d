const {chromium}=require('playwright');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-gl=angle','--use-angle=metal','--enable-webgl','--ignore-gpu-blocklist']});
 try{
  const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await page.route('**/index.html',async route=>{const response=await route.fetch();let body=await response.text();body=body.replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,renderer,scene,firstRegion,waterSystem};\n    const clock = new THREE.Clock();');body=body.replace('      diving.update(dt, t);','      if(!window.freezeDive) diving.update(dt, t);');await route.fulfill({response,body});});
  await page.goto('http://127.0.0.1:8765/index.html');await page.waitForFunction(()=>window.qa,{},{timeout:60000});await page.waitForTimeout(1800);
  await page.screenshot({path:'outputs/first-region/home.png'});
  await page.evaluate(()=>{const q=qa;q.gameplay.art.state.manualCamera=true;const c=q.controls;c.minDistance=1;c.maxDistance=500;c.minPolarAngle=0;c.maxPolarAngle=Math.PI;c.minAzimuthAngle=-Infinity;c.maxAzimuthAngle=Infinity;c.target.set(0,0,-5);q.camera.position.set(-138,190,155);c.update()});
  await page.waitForTimeout(800);await page.screenshot({path:'outputs/first-region/overview.png'});
  const cleanOverview=await page.addStyleTag({content:'body > :not(#canvas-container){display:none!important}'});await page.screenshot({path:'outputs/first-region/overview-art.png'});await cleanOverview.evaluate(e=>e.remove());
  await page.evaluate(()=>{qa.controls.target.set(49.56,8,-67.54);qa.camera.position.set(28.56,35,-23.54);qa.controls.update()});
  await page.waitForTimeout(500);await page.screenshot({path:'outputs/first-region/bridge.png'});
  await page.evaluate(()=>qa.diving.diveHere());await page.waitForFunction(()=>qa.diving.phase==='swim');
  await page.screenshot({path:'outputs/first-region/underwater-entry.png'});
  await page.evaluate(()=>qa.gameplay.art.explorerGroup.position.set(0,-75,-43));await page.waitForTimeout(1000);await page.screenshot({path:'outputs/first-region/threshold.png'});
  await page.evaluate(()=>{window.freezeDive=true;const q=qa,d=q.gameplay.art.explorerGroup;d.position.set(0,-183,-107);q.diving.update(.016,10);q.diving.art.update(.016,10,q.camera,d);q.camera.position.set(0,-169,-103);q.camera.lookAt(0,-212,-134);q.camera.updateMatrixWorld(true)});
  await page.waitForTimeout(500);await page.screenshot({path:'outputs/first-region/trench-reveal.png'});
  const cleanTrench=await page.addStyleTag({content:'body > :not(#canvas-container){display:none!important}'});await page.screenshot({path:'outputs/first-region/trench-art.png'});await cleanTrench.evaluate(e=>e.remove());
  await page.evaluate(()=>{qa.camera.position.set(-13,-197,-112);qa.camera.lookAt(2,-212,-133);qa.camera.updateMatrixWorld(true)});await page.waitForTimeout(500);await page.screenshot({path:'outputs/first-region/wreck.png'});
  const report=await page.evaluate(()=>({buildings:qa.firstRegion.buildings.length,outerBuildings:qa.firstRegion.outerCity.placements.length,outerBatches:qa.firstRegion.outerCity.batches,walls:qa.firstRegion.walls.length,scale:qa.firstRegion.buildings.every(g=>g.scale.x===1.2&&g.scale.y===1.2&&g.scale.z===1.2),corals:qa.diving.art.trench.corals.length,ship:qa.diving.art.trench.ship.userData,floor:qa.diving.art.trench.floorAt(0,-132),calls:qa.renderer.info.render.calls,triangles:qa.renderer.info.render.triangles}));
  fs.writeFileSync('outputs/first-region/visual-report.json',JSON.stringify({report,errors},null,2));console.log({report,errors});
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
