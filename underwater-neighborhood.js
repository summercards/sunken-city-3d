// Human-scale coastal homes and the everyday remains of a submerged neighbourhood.
export function createUnderwaterNeighborhood({T,root,group,box,rock,mesh,stem,buildings,solidBuildings}) {
  const props=[], coralSites=[];
  const v=(x,y,z)=>new T.Vector3(x,y,z);
  const cylinder=new T.CylinderGeometry(1,1,1,12);
  const shard=new T.BufferGeometry();
  shard.setAttribute('position',new T.Float32BufferAttribute([-.5,-.5,0,.5,-.5,0,.28,-.04,0,.28,-.04,0,.5,-.5,0,.5,.5,0],3));shard.computeVertexNormals();
  const shards=[shard];
  for(const points of [[-.5,-.5,0,.5,-.5,0,-.19,.09,0,-.5,-.5,0,-.19,.09,0,-.5,.35,0],[-.5,.5,0,-.5,-.5,0,-.12,.2,0,.5,.5,0,.12,.32,0,.5,-.12,0]]){const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(points,3));geo.computeVertexNormals();shards.push(geo);}
  const palettes=[['#cbbf99','#719d9b'],['#9cb8ab','#9c7666'],['#c6a89c','#6d939e'],['#b8c5b1','#8c9c6a']];
  function child(parent,x,y,z,angle=0){const g=new T.Group();g.position.set(x,y,z);g.rotation.y=angle;parent.add(g);return g;}
  function rail(g,x,y,z,w){
    box(g,'#71908c',x,y+.85,z,w,.09,.09);
    for(let k=0;k<=Math.floor(w/.45);k++)box(g,'#8baba2',x-w/2+k*w/Math.floor(w/.45),y+.45,z,.055,.85,.055);
  }
  // Window openings are actual gaps between wall segments, with a dark interior behind them.
  function facade(g,width,height,paint,id){
    const bays=Math.max(2,Math.floor(width/2.5)),span=width/bays,ww=1.25,wh=1.55;
    for(let f=0;f<height;f++)for(let j=0;j<bays;j++){
      const x=-width/2+(j+.5)*span,y=f*3.2,idw=id*19+f*5+j,broken=idw%4!==0;
      box(g,paint,x,y+.48,0,span,.96,.3);
      box(g,paint,x,y+2.86,0,span,.68,.3);
      for(const sign of [-1,1])box(g,paint,x+sign*(ww/2+(span-ww)/4),y+1.74,0,(span-ww)/2,1.56,.3);
      box(g,'#24434c',x,y+1.74,-.42,ww+.08,wh+.1,.06);
      for(const sign of [-1,1]){
        box(g,'#d8d3b7',x+sign*(ww/2+.045),y+1.74,.19,.09,wh+.15,.15);
        box(g,'#d8d3b7',x,y+1.74+sign*(wh/2+.05),.2,ww+.18,.1,.18);
      }
      box(g,'#9db7ac',x,y+.9,.3,ww+.32,.14,.5);
      if(broken){
        const glass=mesh(g,shards[idw%3],'#88b9b7',x,y+1.74,.13,ww,wh,1);glass.rotation.z=idw%2?Math.PI:0;
        if(idw%11===0){const board=box(g,'#8b927b',x,y+1.62,.29,1.48,.18,.09);board.rotation.z=-.22;}
        if(idw%3===0){const bar=box(g,'#8f9c92',x+.12,y+1.7,.23,.07,1.3,.06);bar.rotation.z=.24;}
        // Uneven brick scars beside the sill, not a repeated crack decal.
        box(g,'#8f9383',x+.7,y+.83,.2,.25,.22,.1);
        box(g,'#aa9a7d',x+.86,y+1.03,.2,.28,.12,.1);
      }else{
        box(g,'#558b95',x,y+1.74,.12,ww,wh,.035);
        box(g,'#b9c9b3',x,y+1.74,.2,.06,wh,.08);
        box(g,'#b9c9b3',x,y+1.64,.2,ww,.06,.08);
      }
      if(f===1&&j===0&&id%2===0){
        const shutter=child(g,x-.82,y+1.74,.28,-.3);
        box(shutter,'#6b9b8d',0,0,0,.36,1.6,.09);
        for(let k=0;k<5;k++)box(shutter,'#91b4a2',0,-.55+k*.26,.06,.33,.065,.08);
      }
    }
  }
  // Each home sits on an old street terrace. Rock foundations, rather than 25 identical floors, continue into the depths.
  const specs=[
    [-14,1,7.6,6.8,-14,5,0], [14,-6,8,7,-14,4,3],
    [-18,-17,6.5,7,-18,2,2], [16,21,8,6,-14,5,3],
    [-19,26,6.5,7,-25,3,1], [8,-33,7,6,-14,5,2],
    [-8,-35,7.5,6,-18,4,0], [20,-24,6,7,-40,3,3],
    [-12,-19,6.5,6,-46,3,1], [14,12,7,6,-59,2,2],
    [-9,21,5.8,6,-73,2,0], [8,-23,6,5.5,-74,2,3]
  ];
  specs.forEach(([x,z,w,d,base,floors,type],i)=>{
    const g=group(x,base,z,'submerged-residence-'+i),h=floors*3.2,[paint,accent]=palettes[type];
    buildings.push(g);g.userData={width:w,depth:d,top:base+h,bottom:base,floorHeight:3.2,floors,type,foundationBottom:-76};
    solidBuildings.push({x,z,w:w/2+.2,d:d/2+.2,top:base+h+1,bottom:base});
    const foundationHeight=base+76;
    if(foundationHeight>0){
      rock(g,'#507e85',0,-foundationHeight/2,0,w*.8,foundationHeight*.57,d*.9);
      solidBuildings.push({x,z,w:w*.48,d:d*.48,top:base,bottom:-76});
    }
    box(g,'#929d8d',0,-.35,0,w+2,.7,d+2.6);
    for(let k=0;k<3;k++)box(g,'#bac4ab',w*.22,-.05-k*.15,d/2+.6+k*.25,1.7,.2,.35);
    // Four differently oriented facades, divided into rooms by solid floor plates.
    facade(child(g,0,0,d/2),w,floors,paint,i);
    facade(child(g,0,0,-d/2,Math.PI),w,floors,paint,i+1);
    facade(child(g,w/2,0,0,Math.PI/2),d,floors,paint,i+2);
    facade(child(g,-w/2,0,0,-Math.PI/2),d,floors,paint,i+3);
    for(let f=0;f<=floors;f++)box(g,f===floors?'#aab39b':'#7c9690',0,f*3.2,0,w+.12,.2,d+.12);
    box(g,'#507b7b',w*.22,1.2,d/2+.22,1.25,2.4,.18);
    box(g,'#bfb08a',w*.22+.4,1.1,d/2+.34,.07,.24,.06);
    // Pitched ceramic roofs, flat terraces, and incomplete roof rooms give distinct silhouettes.
    if(type===0||type===2){
      for(const sign of [-1,1]){
        const roof=box(g,type===0?'#b17e69':'#849c9e',sign*w*.25,h+.65,0,w*.56,.18,d+.65);roof.rotation.z=-sign*.3;
        for(let k=0;k<Math.floor(d/.55);k++){
          const seam=box(g,type===0?'#c39a7b':'#a1b6ac',sign*w*.25,h+.76,-d/2+k*.55,w*.55,.055,.045);seam.rotation.z=-sign*.3;
        }
      }
      box(g,'#b0a68d',-w*.25,h+1.35,-d*.24,.7,1.5,.75);
      box(g,'#7d8e87',-w*.25,h+2.1,-d*.24,.86,.14,.9);
    }else{
      for(const sign of [-1,1])box(g,paint,0,h+.45,sign*d/2,w,.8,.22);
      box(g,paint,-w/2,h+.4,0,.23,.75,d);
      box(g,accent,w*.22,h+.9,-d*.2,w*.35,1.8,d*.4);
      mesh(g,cylinder,'#91aaa4',-w*.25,h+.8,-d*.2,.68,1.45,.68);
      mesh(g,cylinder,'#c0c9b2',-w*.25,h+1.56,-d*.2,.72,.12,.72);
    }
    // A domestic balcony, AC compressor and drainpipe, at believable human scale.
    if(type!==2){
      box(g,'#a9b6a0',-w*.19,3.2,d/2+.65,w*.52,.22,1.4);
      rail(g,-w*.19,3.3,d/2+1.3,w*.52);
      box(g,'#b5bda6',w*.25,4.5,d/2+.4,.95,.65,.55);
      mesh(g,cylinder,'#4f7477',w*.25,4.5,d/2+.7,.23,.055,.23).rotation.x=Math.PI/2;
      for(let j=0;j<3;j++)box(g,'#94a797',w*.25-.3,4.3+j*.16,d/2+.71,.12,.04,.05);
    }
    stem(g,v(-w/2-.16,.2,d/2),v(-w/2-.16,h,d/2),.085,'#8f9b83');
    if(type===3){
      for(let k=0;k<7;k++){const awning=box(g,k%2?'#e0c98e':'#739e98',-1.5+k*.5,2.7,d/2+.6,.5,.12,1.4);awning.rotation.x=.18;}
      box(g,'#8c9e8c',-.1,2.95,d/2+.2,3.5,.35,.18);
    }
    for(let j=0;j<3;j++){
      rock(g,'#9caa95',-w/2+.6+j*.5,.2,d/2+.7,.3,.2,.25);
      coralSites.push([x-w*.35+j*w*.34,base+.12,z+d/2+.65]);
    }
    // Small plaster losses expose masonry on the corners.
    for(let j=0;j<7;j++)box(g,j%2?'#998d79':'#80928b',-w/2+.18+(j%2)*.22,.3+j*.36,d/2+.18,.4,.15,.06);
  });
  function lamp(x,y,z,lean=0){
    const g=group(x,y,z,'submerged-streetlamp');props.push(g);g.rotation.z=lean;
    box(g,'#7b9991',0,.15,0,.45,.3,.45);
    stem(g,v(0,0,0),v(0,3.9,0),.085,'#637e7e');
    stem(g,v(0,3.9,0),v(.75,4.2,0),.075,'#637e7e');
    box(g,'#8fa298',.85,4.08,0,.65,.17,.38);box(g,'#d6d7a4',.85,3.98,0,.48,.06,.26);
  }
  // Broken street bridge: two standing abutments, torn concrete fingers, exposed rods and a dropped deck.
  for(const sign of [-1,1]){
    const x=sign*9.8,y=-27,z=-13,g=group(x,y,z,'collapsed-bridge-abutment');props.push(g);
    box(g,'#879c91',0,0,0,9,.65,4);box(g,'#647f7f',0,.35,0,9,.08,3.25);
    box(g,'#b7bda0',0,.43,-1.85,9,.22,.25);box(g,'#b7bda0',0,.43,1.85,9,.22,.25);
    for(let j=0;j<4;j++){
      box(g,'#b9b79b',-3+j*2,.41,0,.8,.025,.12);
      box(g,'#849e94',-3+j*2,1.03,-1.85,.13,1.15,.15);
    }
    box(g,'#a8b8a3',0,1.5,-1.85,8.8,.12,.16);
    box(g,'#708e86',sign*2,-24.3,0,1.5,48,2.8);
    solidBuildings.push({x,z,w:4.5,d:2,top:y+.5,bottom:y-.4});
    solidBuildings.push({x:x+sign*2,z,w:.75,d:1.4,top:y-.3,bottom:-75.3});
    for(let j=0;j<6;j++){
      const xx=-sign*(4.3+(j%3)*.17),zz=-1.5+j*.57;
      rock(g,'#a2b09c',xx,-.05,zz,.6,.34,.4);
      stem(g,v(xx,.1,zz),v(xx-sign*.9,-.2,zz+.1),.035,'#8e7965');
    }
    lamp(x+sign*2,y+.5,z+1.65,sign*.14);
  }
  const deck=group(1,-73.4,-12,'fallen-bridge-deck');props.push(deck);deck.rotation.set(.08,.22,.12);
  solidBuildings.push({x:1,z:-12,w:3.8,d:2.6,top:-72.2,bottom:-74.1});
  box(deck,'#8b9f94',0,.4,0,7,.65,3.8);box(deck,'#597e81',0,.76,0,6.7,.06,3.25);
  for(let j=0;j<4;j++)box(deck,'#c0ba94',-2.4+j*1.6,.8,0,.8,.025,.12);
  function car(x,y,z,color,type,angle){
    const g=group(x,y,z,type?'submerged-delivery-van':'submerged-car');props.push(g);g.rotation.set(.04,angle,.07);
    const length=type?4.6:3.8;
    box(g,'#45676b',0,.33,0,1.68,.22,length-.15);
    box(g,color,0,.68,0,1.8,.65,length);
    box(g,'#254750',0,1.15,-.2,1.55,.7,type?2.9:2.05);
    box(g,color,0,1.56,-.2,1.64,.17,type?3:2.2);
    for(const sx of [-1,1]){
      for(const zz of [-.95,.7])box(g,color,sx*.81,1.15,zz,.095,.75,.12);
      box(g,color,sx*.84,.96,-.15,.065,.08,2.2);
      box(g,'#b0b8a0',sx*.92,.83,.35,.045,.06,.22);
      for(const zz of [-length*.32,length*.32]){
        mesh(g,cylinder,'#30494e',sx*.88,.38,zz,.37,.22,.37).rotation.z=Math.PI/2;
        mesh(g,cylinder,'#8a9d95',sx*1.005,.38,zz,.17,.025,.17).rotation.z=Math.PI/2;
      }
      box(g,'#c5c7a1',sx*.59,.7,length/2+.02,.35,.19,.06);
      box(g,'#9d7965',sx*.6,.75,-length/2-.025,.25,.16,.05);
    }
    box(g,'#809b92',0,.44,length/2+.09,1.65,.12,.12);
    mesh(g,shard,'#91b9b6',-.3,1.2,1, .6,.55,1);
    for(let j=0;j<4;j++)rock(g,j%2?'#718b75':'#a08c6c',-.6+j*.4,.99,length*.35,.23,.06,.24);
    solidBuildings.push({x,z,w:2.5,d:2.5,top:y+1.7,bottom:y-.2});
  }
  // Parking remnants on the residential ledges and a pair of vehicles on the lower seabed.
  car(-9.3,-17.5,6.4,'#c4a16e',0,.4);
  car(9,-30.5,-11,'#a57978',1,-.35);
  car(-5,-74.6,9,'#86a9a0',0,-.55);
  car(5,-74.6,16,'#b3aa83',1,.7);
  for(const p of [[-7.5,-17.6,7,.08],[8,-30.6,-9,-.18],[-7,-45.6,-15,.12],[8,-58.6,16,-.22],[-6,-74,13,.5],[8,-74,19,-.2]])lamp(...p);
  return {props,coralSites};
}
