const {chromium}=require('playwright');const assert=require('node:assert/strict');
(async()=>{const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});try{
const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
await page.route('**/index.html',async r=>{const res=await r.fetch();let body=await res.text();body=body.replace('    const clock = new THREE.Clock();','    window.qa={gridView,harbor,gameplay,sceneArt,scene,camera,controls};\n    const clock = new THREE.Clock();');await r.fulfill({response:res,body});});
await page.goto('http://127.0.0.1:8765/index.html');await page.waitForFunction(()=>window.qa);await page.waitForTimeout(2300);await page.screenshot({path:'outputs/water-character-view.png'});
const result=await page.evaluate(()=>{const q=qa;const d=q.gridView.texture.image.data;return {binary:[...new Set(d)],visible:d.filter((v,i)=>i%4===0&&v===255).length,polar:q.controls.getPolarAngle(),azimuth:q.controls.getAzimuthalAngle(),sites:q.gameplay.art.buildSites.map(s=>({id:s.id,visible:q.gridView.isVisible(s.hoverAnchor)}))};});
assert.deepEqual(result.binary.sort((a,b)=>a-b),[0,255]);assert.equal(result.visible,225);assert(Math.abs(result.polar-Math.PI/4)<.001);assert(Math.abs(result.azimuth+Math.PI/4)<.001);
const transition=await page.evaluate(()=>{const q=qa;q.gameplay.art.state.manualCamera=true;q.controls.target.x+=9;q.camera.position.x+=9;q.gridView.update(99);const unchanged=q.gridView.pending.size===0; q.gameplay.art.explorerGroup.position.x+=9;q.scene.updateMatrixWorld(true);q.gridView.update(100);const before=q.gridView.texture.image.data.filter((v,i)=>i%4===0&&v===255).length;const waiting=q.gridView.pending.size;q.gridView.update(101);return{unchanged,before,waiting,after:q.gridView.texture.image.data.filter((v,i)=>i%4===0&&v===255).length};});assert(transition.unchanged);assert(transition.waiting>0);assert(transition.before<transition.after);assert.equal(transition.after,225);
const boatFollow=await page.evaluate(()=>{
 const q=qa,a=q.gameplay.art,mode=a.state.workerMode,old=a.boatAnchorGroup.position.clone();
 a.state.workerMode='ROWING';a.boatAnchorGroup.position.set(30,1.12,-21);q.scene.updateMatrixWorld(true);q.gridView.update(110);
 const center=q.gridView.center.toArray();a.state.workerMode=mode;a.boatAnchorGroup.position.copy(old);q.scene.updateMatrixWorld(true);q.gridView.update(112);q.gridView.update(114);
 return center;
});assert.deepEqual(boatFollow,[31.5,-19.5]);
const play=await page.evaluate(()=>{
 const q=qa,{state,buildSites}=q.gameplay.art;let t=200;
 const results=[];
 for(const id of ['rooftop_planter','shallow_aquaculture']){
  const site=buildSites.find(s=>s.id===id);site.storedCoins=0;state.coins=200;
  q.gameplay.updateOverlays();document.querySelector(`[data-site-id="${id}"]`).click();
  for(let i=0;i<5000&&site.level===0;i++){t+=.05;q.gameplay.updateGameplay(.05,t);q.sceneArt.update(t);q.harbor.update(t);}
  results.push({id,level:site.level,mode:state.workerMode,zone:state.currentZone});
 }
 return results;
});assert(play.every(s=>s.level===1&&s.mode==='IDLE_ASHORE'));assert.deepEqual(errors,[]);console.log(JSON.stringify({result,transition,boatFollow,play,errors},null,2));
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});
