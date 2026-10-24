const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1200,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/index.html',async route=>{const response=await route.fetch();const body=(await response.text()).replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,scene,renderer};\n    const clock = new THREE.Clock();');await route.fulfill({response,body});});
  await page.goto('http://localhost:8765/index.html');await page.waitForFunction(()=>window.qa);
  await page.evaluate(()=>{const p=qa.gameplay.art.swimParts;window.before=p.detail.elbows.concat(p.detail.knees,p.detail.ankles).map(o=>o.rotation.toArray());qa.diving.start(new qa.THREE.Vector3(0,1.12,12));});
  await page.waitForFunction(()=>qa.diving.phase==='swim');await page.waitForTimeout(1000);
  const capture=async(name)=>{
   const data=await page.evaluate(()=>{const {THREE:T,renderer,scene,gameplay}=qa;const target=gameplay.art.swimParts.explorerBodyPivot.localToWorld(new T.Vector3(0,.55,0));const cam=new T.PerspectiveCamera(35,1200/900,.05,200);cam.position.copy(target).add(new T.Vector3(3,2,-5));cam.lookAt(target);renderer.render(scene,cam);return renderer.domElement.toDataURL('image/png');});
   fs.writeFileSync(`outputs/character-${name}.png`,Buffer.from(data.split(',')[1],'base64'));
  };
  await capture('hover');
  const idle=await page.evaluate(()=>qa.gameplay.art.swimParts.explorerBodyPivot.rotation.x);
  await page.keyboard.down('KeyW');await page.waitForTimeout(1200);
  const moving=await page.evaluate(()=>({tilt:qa.gameplay.art.swimParts.explorerBodyPivot.rotation.x,knees:qa.gameplay.art.swimParts.detail.knees.map(o=>o.rotation.x)}));
  assert(moving.tilt>idle+.4);assert(Math.abs(moving.knees[0]-moving.knees[1])>.025);
  await capture('swim');await page.keyboard.up('KeyW');
  await page.keyboard.down('KeyQ');await page.waitForTimeout(900);await capture('descend');await page.keyboard.up('KeyQ');
  await page.keyboard.down('KeyE');await page.waitForTimeout(900);await capture('ascend');await page.keyboard.up('KeyE');
  await page.click('#dive-button');await page.waitForFunction(()=>qa.diving.phase==='surface');
  assert(await page.evaluate(()=>{const r=qa.gameplay.art.swimParts.detail;return ![r.gear,r.mask,r.regulator,...r.fins].some(o=>o.visible)&&JSON.stringify(r.elbows.concat(r.knees,r.ankles).map(o=>o.rotation.toArray()))===JSON.stringify(window.before)}));
  assert.deepEqual(errors,[]);
  console.log('PASS: speed-dependent trim, articulated alternating kick, all dive equipment hidden and joints restored after surfacing; four close-up renders; no runtime errors.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
