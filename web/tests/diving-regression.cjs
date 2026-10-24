const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_BIN||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await page.route('**/index.html',async route=>{const response=await route.fetch();const body=(await response.text()).replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,scene,renderer,waterSystem};\n    const clock = new THREE.Clock();');await route.fulfill({response,body});});
  await page.goto('http://localhost:8765/index.html');await page.waitForFunction(()=>window.qa);await page.waitForTimeout(700);
  await page.evaluate(()=>window.original={parent:qa.gameplay.art.explorerGroup.parent.uuid,position:qa.gameplay.art.explorerGroup.position.toArray(),fov:qa.camera.fov,fog:qa.scene.fog});
  // 区域化下潜：人已经在某片水域（岸边/船上）时，按潜水就该直接下去，不再要求点选海面。
  await page.click('#dive-button');
  await page.waitForFunction(()=>qa.diving.phase==='swim');
  assert.equal(await page.evaluate(()=>qa.diving.zone),'zone1','应当记录下潜所在区块');
  await page.waitForTimeout(900);
  const view=await page.evaluate(()=>({under:qa.camera.position.y<1.12,range:qa.camera.position.distanceTo(qa.gameplay.art.explorerGroup.position),fov:qa.camera.fov,water:qa.waterSystem.surface.visible,fish:qa.diving.art.schools.reduce((n,s)=>n+s.members.length,0)}));
  assert(view.under&&view.range<17&&!view.water&&view.fov===55&&view.fish===126,JSON.stringify(view));
  assert.equal(await page.locator('.resource-orb:visible').count(),0);
  await page.screenshot({path:'outputs/underwater-city-swim.png'});
  const pos=()=>page.evaluate(()=>qa.gameplay.art.explorerGroup.position.toArray());
  let before=await pos();await page.keyboard.down('KeyW');await page.waitForTimeout(650);await page.keyboard.up('KeyW');let after=await pos();assert(after[2]<before[2]-.7,'W should move toward view direction');
  before=await pos();const right=await page.locator('#dive-right').boundingBox();await page.mouse.move(right.x+15,right.y+15);await page.mouse.down();await page.waitForTimeout(650);await page.mouse.up();after=await pos();assert(after[0]>before[0]+.7,'touch pad should support holding');
  before=await pos();await page.keyboard.down('KeyQ');await page.waitForTimeout(650);await page.keyboard.up('KeyQ');after=await pos();assert(after[1]<before[1]-.7,'Q descends');
  before=await pos();await page.keyboard.down('KeyE');await page.waitForTimeout(650);await page.keyboard.up('KeyE');after=await pos();assert(after[1]>before[1]+.6,'E ascends');
  const fishA=await page.evaluate(()=>qa.diving.art.schools[0].members[0].g.position.toArray());await page.waitForTimeout(700);const fishB=await page.evaluate(()=>qa.diving.art.schools[0].members[0].g.position.toArray());assert.notDeepEqual(fishA,fishB);
  // Remote click must swim there, then search automatically; movement interrupts the action.
  const tag=page.getByRole('button',{name:'搜索珊瑚花园宝箱'});
  await tag.click();assert(await page.evaluate(()=>qa.diving.navigating));
  await page.keyboard.down('KeyD');await page.waitForTimeout(180);await page.keyboard.up('KeyD');assert(!await page.evaluate(()=>qa.diving.navigating));
  const count=()=>page.evaluate(()=>({wood:qa.gameplay.art.state.wood,parts:qa.gameplay.art.state.parts}));const initial=await count();
  await tag.click();await page.waitForFunction(()=>!document.getElementById('dive-progress').hidden,{},{timeout:25000});
  await page.waitForTimeout(650);await page.screenshot({path:'outputs/underwater-city-treasure.png'});
  await page.waitForFunction(()=>document.getElementById('dive-progress').hidden);
  const reward=await count();assert.equal(reward.wood,initial.wood+2);assert.equal(reward.parts,initial.parts+2);assert(await tag.isHidden());
  // Examine deeper layers: palette darkens, floor and separate low shelves become readable.
  await page.evaluate(()=>qa.gameplay.art.explorerGroup.position.set(0,-49,0));await page.waitForTimeout(1400);await page.screenshot({path:'outputs/underwater-deep-reef.png'});
  assert(await page.evaluate(()=>qa.camera.position.y<qa.gameplay.art.explorerGroup.position.y+13));
  await page.click('#dive-button');await page.waitForFunction(()=>qa.diving.phase==='surface');
  const restored=await page.evaluate(()=>({parent:qa.gameplay.art.explorerGroup.parent.uuid,pos:qa.gameplay.art.explorerGroup.position.toArray(),fov:qa.camera.fov,water:qa.waterSystem.surface.visible,mode:qa.gameplay.art.state.workerMode,original:window.original.position,parent0:window.original.parent,fog:qa.scene.fog===window.original.fog}));
  assert.deepEqual(restored.pos,restored.original);assert.equal(restored.parent,restored.parent0);assert(restored.water&&restored.fov===31&&restored.fog);assert.equal(restored.mode,'IDLE_ASHORE');
  await page.screenshot({path:'outputs/underwater-return-surface.png'});
  // Collected treasure stays opened on re-entry; parenting from a boat must be restored.
  await page.evaluate(()=>{const a=qa.gameplay.art;qa.scene.getObjectByName('nonexistent');a.boatAnchorGroup.add(a.explorerGroup);a.explorerGroup.position.set(0,.5,0);a.state.workerMode='BOAT_IDLE';window.boatParent=a.explorerGroup.parent.uuid;qa.diving.start(new qa.THREE.Vector3(-7,1.12,8));});
  await page.waitForFunction(()=>qa.diving.phase==='swim');assert(await tag.isHidden());await page.click('#dive-button');await page.waitForFunction(()=>qa.diving.phase==='surface');
  assert(await page.evaluate(()=>qa.gameplay.art.explorerGroup.parent.uuid===window.boatParent&&qa.gameplay.art.state.workerMode==='BOAT_IDLE'));
  assert.deepEqual(errors,[]);console.log('PASS: water entry, close underwater camera, visible avatar, 126 moving fish, keyboard/touch/depth movement, click-to-swim and manual cancellation, rewards, no duplicate collection, surface and boat restoration; no browser/shader errors.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
