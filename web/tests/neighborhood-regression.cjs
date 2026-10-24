const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try{
 const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 await page.route('**/index.html',async r=>{const response=await r.fetch();await r.fulfill({response,body:(await response.text()).replace('    const clock = new THREE.Clock();','    window.qa={THREE,diving,gameplay,camera,controls,renderer,scene};\n    const clock = new THREE.Clock();')});});
 await page.goto('http://localhost:8765/index.html');await page.waitForFunction(()=>window.qa);
 await page.evaluate(()=>qa.diving.start(new qa.THREE.Vector3(-7,1.12,8)));await page.waitForFunction(()=>qa.diving.phase==='swim');await page.waitForTimeout(700);
 await page.screenshot({path:'outputs/underwater-residential-city.png'});
 for(let i=0;i<5;i++){
   await page.evaluate(i=>qa.diving.chests[i].tag.click(),i);
   await page.waitForFunction(i=>qa.diving.chests[i].opening>0,i,{timeout:45000});console.log('Treasure reachable:',i);
   if(i===1){await page.screenshot({path:'outputs/underwater-broken-bridge.png'});}
 }
 for(const [name,pos] of [['underwater-residential-street',[0,-70,24]],['underwater-bridge-detail',[0,-24,-3]]]){
   await page.evaluate(p=>qa.gameplay.art.explorerGroup.position.set(...p),pos);await page.waitForTimeout(1200);await page.screenshot({path:'outputs/'+name+'.png'});
 }
 assert.deepEqual(errors,[]);console.log('PASS: all five treasure routes remain reachable through the residential city.');
}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
