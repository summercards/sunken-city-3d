const {chromium}=require('playwright');const assert=require('node:assert/strict');
(async()=>{const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});try{
const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
await page.route('**/index.html',async r=>{const res=await r.fetch();let body=await res.text();body=body.replace('    const clock = new THREE.Clock();','    window.qa={harbor,gameplay,sceneArt,scene,camera,controls,renderer};\n    const clock = new THREE.Clock();');await r.fulfill({response:res,body});});
await page.goto('http://127.0.0.1:8765/index.html');await page.waitForFunction(()=>window.qa);await page.waitForTimeout(2300);await page.screenshot({path:'outputs/water-character-view.png'});
// The vision mask is retired: nothing may gate visibility, so the whole harbor is always readable.
const result=await page.evaluate(()=>{
 const q=qa;
 return {worldVisible:typeof q.gameplay.art.state.worldVisible,polar:q.controls.getPolarAngle(),azimuth:q.controls.getAzimuthalAngle(),
   sites:q.gameplay.art.buildSites.map(s=>({id:s.id,level:s.level}))};
});
assert.equal(result.worldVisible,'undefined');
assert(Math.abs(result.polar-Math.PI/4)<.001);assert(Math.abs(result.azimuth+Math.PI/4)<.001);
// No lingering mask in any compiled shader.
const masked=await page.evaluate(()=>{let n=0;qa.renderer.info.programs.forEach(p=>{if(p.cacheKey&&/grid-view/.test(p.cacheKey))n++;});return n;});
assert.equal(masked,0);
const play=await page.evaluate(()=>{
 const q=qa,{state,buildSites}=q.gameplay.art;let t=200;
 const results=[];
 for(const id of ['rooftop_planter','shallow_aquaculture']){
  const site=buildSites.find(s=>s.id===id);site.storedCoins=0;state.coins=200;state.wood=6;state.parts=4;state.pearl=2;state.shipLevel=2;state.farSeaUnlocked=true;
  q.gameplay.updateOverlays();document.querySelector(`[data-site-id="${id}"]`).click();
  for(let i=0;i<5000&&site.level===0;i++){t+=.05;q.gameplay.updateGameplay(.05,t);q.sceneArt.update(t);q.harbor.update(t);}
  results.push({id,level:site.level,mode:state.workerMode,zone:state.currentZone});
 }
 return results;
});assert(play.every(s=>s.level===1&&s.mode==='IDLE_ASHORE'));assert.deepEqual(errors,[]);console.log(JSON.stringify({result,masked,play,errors},null,2));
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});
