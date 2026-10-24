const { chromium } = require('playwright');
const assert = require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  await page.route('**/index.html',async route=>{const response=await route.fetch();await route.fulfill({response,body:(await response.text()).replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,renderer,scene};\n    const clock = new THREE.Clock();')});});
  await page.goto('http://localhost:8765/index.html');await page.waitForFunction(()=>window.qa);
  await page.evaluate(()=>qa.diving.start(new qa.THREE.Vector3(-7,1.12,8)));await page.waitForFunction(()=>qa.diving.phase==='swim');await page.waitForTimeout(500);
  const layout=await page.evaluate(()=>{
    const a=qa.diving.art,b=a.buildings.map(g=>g.userData);
    return {count:b.length,emerging:b.filter(v=>v.top>1.12).length,base:b.every(v=>v.foundationBottom<=-75),residential:b.every(v=>v.floors>=2&&v.floors<=5),variants:new Set(b.map(v=>v.type)).size,props:a.neighborhood.props.map(g=>g.name),floor:b.every(v=>v.floorHeight===3.2),shallow:a.boundsAt(-12),deep:a.boundsAt(-70),bowl:!!a.root.getObjectByName('continuous-tapered-rock-basin'),calls:qa.renderer.info.render.calls,corals:a.root.children.filter(g=>g.name==='reef-coral').length};
  });
  assert(layout.count>=10&&layout.emerging>=3&&layout.base&&layout.floor&&layout.bowl&&layout.residential&&layout.variants>=4);
  assert(layout.deep.x<layout.shallow.x*.6&&layout.deep.z<layout.shallow.z);
  assert(layout.corals>=240);
  assert(layout.props.includes('fallen-bridge-deck')&&layout.props.filter(n=>n.includes('car')||n.includes('van')).length>=4&&layout.props.filter(n=>n==='submerged-streetlamp').length>=6);
  const bubbleA=await page.evaluate(()=>Array.from(qa.diving.art.bubbleMesh.instanceMatrix.array.slice(0,16)));
  await page.waitForTimeout(700);const bubbleB=await page.evaluate(()=>Array.from(qa.diving.art.bubbleMesh.instanceMatrix.array.slice(0,16)));assert.notDeepEqual(bubbleA,bubbleB);
  await page.screenshot({path:'outputs/underwater-residential-city.png'});
  // Drag upward to inspect the water ceiling; default descent still uses a downward camera.
  await page.mouse.move(700,650);await page.mouse.down({button:'right'});await page.mouse.move(700,340,{steps:12});await page.mouse.up({button:'right'});await page.waitForTimeout(1300);
  const optics=await page.evaluate(()=>({renders:qa.diving.art.optics.renders,size:qa.diving.art.optics.uniforms.resolution.value.toArray(),direction:qa.camera.getWorldDirection(new qa.THREE.Vector3()).y}));
  assert(optics.renders>0&&optics.size[0]===1440&&optics.direction>0,'Looking up must render real scene transmission');
  await page.screenshot({path:'outputs/underwater-refracting-surface.png'});
  // Freeze world/camera and compare only procedural interface phases against the same captured scene.
  const distortion=await page.evaluate(()=>{
    const {THREE:T,diving,renderer,camera,scene}=qa,optics=diving.art.optics;
    const target=new T.WebGLRenderTarget(256,160),samples=[];const savedTime=optics.uniforms.time.value;
    for(const t of [2,3]){optics.uniforms.time.value=t;renderer.setRenderTarget(target);renderer.render(scene,camera);const pixels=new Uint8Array(256*160*4);renderer.readRenderTargetPixels(target,0,0,256,160,pixels);samples.push(pixels);}
    optics.uniforms.time.value=savedTime;renderer.setRenderTarget(null);target.dispose();let changed=0;
    for(let i=0;i<samples[0].length;i+=4)if(Math.abs(samples[0][i]-samples[1][i])+Math.abs(samples[0][i+1]-samples[1][i+1])>3)changed++;
    return changed;
  });assert(distortion>300,'Interface wave phases must change rendered transmission');
  // Re-enter restores the default oblique view and validate the narrowing physical boundary.
  await page.click('#dive-button');await page.waitForFunction(()=>qa.diving.phase==='surface');
  await page.evaluate(()=>qa.diving.start(new qa.THREE.Vector3(-7,1.12,8)));await page.waitForFunction(()=>qa.diving.phase==='swim');
  await page.evaluate(()=>qa.gameplay.art.explorerGroup.position.set(0,-67,0));await page.waitForTimeout(1000);await page.screenshot({path:'outputs/underwater-enclosed-depth.png'});
  await page.evaluate(()=>qa.gameplay.art.explorerGroup.position.set(0,-67,30.5));await page.keyboard.down('KeyS');await page.waitForTimeout(1800);await page.keyboard.up('KeyS');
  assert(await page.evaluate(()=>qa.diving.art.insideBasin(qa.gameplay.art.explorerGroup.position,1)),'Player cannot leave the visible rock basin');
  assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:true,layout,optics,distortion,errors},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
