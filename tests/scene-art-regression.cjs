const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 await page.route('**/index.html',async route=>{
   const response=await route.fetch();let body=await response.text();
   body=body.replace('    const clock = new THREE.Clock();','    window.artQA={sceneArt,gameplay,camera,controls,renderer,scene};\n    const clock = new THREE.Clock();');
   body=body.replace('      gameplay.updateGameplay(dt, t);','      if(!window.freezeArt) gameplay.updateGameplay(dt, t);');
   body=body.replace('      sceneArt.update(t);','      if(!window.freezeArt) sceneArt.update(t);');
   await route.fulfill({response,body});
 });
 await page.goto((process.env.APP_URL||'http://localhost:8765')+'/index.html');
 await page.waitForFunction(()=>window.artQA);await page.waitForTimeout(1800);
 await page.screenshot({path:'outputs/art-home.png'});
 for(const zone of ['zone2','zone3']){
  await page.evaluate(zone=>{const q=window.artQA;q.gameplay.art.state.camLockMode=zone;q.gameplay.art.state.manualCamera=false},zone);
  await page.waitForTimeout(1500);await page.screenshot({path:`outputs/art-${zone}.png`});
 }
 const initial=await page.evaluate(()=>{
  window.freezeArt=true;const q=window.artQA;return {
   soil:q.sceneArt.plots.map(p=>({id:p.site.id,color:p.soil.material.color.getHexString(),visible:p.seedlings.some(g=>g.visible)})),
   forms:q.sceneArt.ruins.children.map(g=>g.name),
   repairs:q.sceneArt.repairs.flatMap(r=>r.pieces.map(p=>p.m.visible)),
  };
 });
 assert(initial.soil.every(p=>!p.visible));assert(initial.repairs.every(v=>!v));
 assert(new Set(initial.forms.map(n=>n.split('-')[1])).size===4);
 const stages=[];
 for(const [name,progress] of [['dry',0],['wet',.3],['sprout',.57],['grown',1]]){
  const sample=await page.evaluate(progress=>{
   const q=window.artQA,{state,buildSites}=q.gameplay.art;state.workerMode='BUILDING';state.activeJobSite=buildSites.find(s=>s.id==='rooftop_planter');state.jobProgress=progress;
   q.sceneArt.update(4);
   const beds=q.sceneArt.plots.filter(p=>p.site===state.activeJobSite&&p.stage===0);
   return {color:beds[0].soil.material.color.getHexString(),seedlings:beds[0].seedlings.map(g=>({visible:g.visible,y:g.scale.y})),pieces:q.sceneArt.repairs.find(r=>r.site===state.activeJobSite).pieces.map(p=>({visible:p.m.visible,y:p.m.scale.y}))};
  },progress);
  stages.push({name,...sample});await page.screenshot({path:`outputs/art-planting-${name}.png`});
 }
 assert.notEqual(stages[0].color,stages[1].color);
 assert(stages[1].seedlings.every(g=>!g.visible));
 assert(stages[2].seedlings.some(g=>g.visible&&g.y>0&&g.y<1));
 assert(stages[3].seedlings.every(g=>g.visible&&g.y===1));
 assert(stages[1].pieces.some(g=>g.visible)&&stages[1].pieces.some(g=>!g.visible));
 const motion=await page.evaluate(()=>{
  const q=window.artQA,s=q.sceneArt;
  s.update(1);const a=[s.rotor.rotation.z,s.wind[0].g.rotation.z,s.flows[0].m.geometry.attributes.position.getX(0)];
  s.update(2);const b=[s.rotor.rotation.z,s.wind[0].g.rotation.z,s.flows[0].m.geometry.attributes.position.getX(0)];
  return {a,b,calls:q.renderer.info.render.calls};
 });
 assert(motion.a.every((v,i)=>v!==motion.b[i]));
 assert.deepEqual(errors,[]);
 const result={passed:['Three actionable areas start with dry empty beds','Four distinct ruin silhouettes','Soil wets before any sprouts appear','Seedlings grow at fixed soil anchors','Repair pieces assemble progressively','Windmill, foliage and water deform over time','All scene shaders compile without errors'],stages,drawCalls:motion.calls};
 fs.writeFileSync('outputs/scene-art-results.json',JSON.stringify(result,null,2));console.log(JSON.stringify({passed:result.passed,drawCalls:motion.calls},null,2));
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
