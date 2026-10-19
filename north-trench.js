// Northern continuation of the residential basin. The original floor is -75 m;
// the new wreck basin settles at -225 m, another 150 m below it. North is -Z.
export const TRENCH_PROFILE=[
  [-26,-75,14,-10,0],[-42,-79,18,-20,0],[-58,-87,26,-32,2],
  [-74,-106,33,-44,4],[-90,-154,40,-56,5],[-110,-207,46,-70,3],
  [-132,-225,44,-82,0],[-150,-225,36,-93,-3],[-172,-213,10,-103,-4]
];
export function trenchSection(z) {
  if(z> -26||z< -172)return null;
  for(let i=0;i<TRENCH_PROFILE.length-1;i++){
    const a=TRENCH_PROFILE[i],b=TRENCH_PROFILE[i+1];
    if(z<=a[0]&&z>=b[0]){
      const u=(z-a[0])/(b[0]-a[0]),s=u*u*(3-2*u);
      return {floor:a[1]+(b[1]-a[1])*s,half:a[2]+(b[2]-a[2])*s,rim:a[3]+(b[3]-a[3])*s,center:a[4]+(b[4]-a[4])*s};
    }
  }
}
export function trenchFloorAt(x,z){
  const s=trenchSection(z);if(!s)return Infinity;
  const u=Math.abs((x-s.center)/s.half);
  if(u>1.000001)return Infinity;
  return s.floor+(s.rim-s.floor)*Math.min(1,u)**4;
}
export function createNorthTrench({T,root,group,box,rock,mesh,stem,material,solidBuildings}){
  const v=(x,y,z)=>new T.Vector3(x,y,z);
  const positions=[],indices=[],colors=[],rows=112,cols=40;
  const low=new T.Color('#2b6477'),high=new T.Color('#749e9b');
  for(let j=0;j<=rows;j++){
    const z=-26-j*146/rows,s=trenchSection(z);
    for(let i=0;i<=cols;i++){
      const u=-1+2*i/cols,x=s.center+u*s.half;
      positions.push(x,trenchFloorAt(x,z),z);
      const c=low.clone().lerp(high,Math.abs(u)**1.5*.65+(j%7===0?.08:0));colors.push(c.r,c.g,c.b);
    }
  }
  for(let j=0;j<rows;j++)for(let i=0;i<cols;i++){
    const a=j*(cols+1)+i,b=a+cols+1;indices.push(a,a+1,b,b,a+1,b+1);
  }
  const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(positions,3));geo.setAttribute('color',new T.Float32BufferAttribute(colors,3));geo.setIndex(indices);geo.computeVertexNormals();
  const groundMat=material('#ffffff').clone();groundMat.vertexColors=true;groundMat.side=T.DoubleSide;groundMat.onBeforeCompile=material('#ffffff').onBeforeCompile;
  const ground=new T.Mesh(geo,groundMat);ground.name='north-trench-continuous-seabed';ground.receiveShadow=true;root.add(ground);
  // Vertical escarpments continue above the sloping floor. The rim never floats.
  for(const sign of [-1,1]){
    const p=[],ix=[];
    for(let j=0;j<=rows;j++){
      const z=-26-j*146/rows,s=trenchSection(z),x=s.center+sign*s.half;
      p.push(x,s.rim,z,x+sign*6,4,z);
      if(j<rows){const a=j*2;ix.push(a,a+2,a+1,a+1,a+2,a+3);}
    }
    const g=new T.BufferGeometry();g.setAttribute('position',new T.Float32BufferAttribute(p,3));g.setIndex(ix);g.computeVertexNormals();
    const m=material(sign<0?'#497e8c':'#356a7f').clone();m.side=T.DoubleSide;m.onBeforeCompile=material('#497e8c').onBeforeCompile;
    const cliff=new T.Mesh(g,m);cliff.name='north-trench-escarpment';root.add(cliff);
  }
  // A closed far headwall, with a continuous collision boundary at z=-172.
  box(root,'#346c7c',-4,-112,-174,34,226,4);
  // Large attached strata, each planted on the same heightfield used by swimming.
  for(let i=0;i<38;i++){
    const z=-35-i*3.45,s=trenchSection(z),sign=i%2?1:-1,u=.77+(i%3)*.055,x=s.center+sign*s.half*u;
    const y=trenchFloorAt(x,z),h=5+(i%4)*3;
    const r=rock(root,i%3?'#56828c':'#6c9298',x,y+h*.15,z,3.4+(i%3),h*.65,5.5);
    r.rotation.y=i*.53;r.name='trench-attached-stratum';
  }
  // The brink has three old stair remnants, giving a human-scale depth reference.
  for(let i=0;i<3;i++){
    const x=-10-i*2,z=-48-i*8,y=trenchFloorAt(x,z);
    const g=group(x,y+.3,z,'trench-descent-remnant');g.rotation.y=-.1;
    box(g,'#95aca0',0,0,0,7,.4,4);
    for(let j=0;j<5;j++)box(g,'#7c9893',0,-j*.55,-1.5-j*.65,2.1,.35,.75);
    for(const xx of [-2.8,2.8])stem(g,v(xx,.1,1),v(xx,2.4,1),.09,'#80978a');
    stem(g,v(-2.8,2.2,1),v(2.8,2.2,1),.065,'#b1b79a');
  }
  // A 32 m wooden brig, rolled onto a rock shelf, bow toward the approach.
  const ship=group(1,-216,-130,'tilted-pirate-brig');ship.rotation.set(.10,-.28,-.32);
  ship.userData={length:32,heelDegrees:18.3,depth:225};
  const halfWidth=z=>5.2*Math.pow(Math.max(0,1-(z/17)**2),.48);
  // Curved plank strakes follow the tapered hull, with missing bow planks.
  for(let j=0;j<21;j++){
    const z=-15.5+j*1.5,w=halfWidth(z),next=halfWidth(z+.72),prev=halfWidth(z-.72);
    for(let level=0;level<5;level++)for(const sign of [-1,1]){
      if((j===15||j===16)&&level>1&&sign===-1)continue;
      const f=.43+level*.14,x=sign*w*f,y=-3.1+level*.68;
      const plank=box(ship,['#564e45','#6c6250','#817359','#928166','#6a6252'][level],x,y,z,.32,.62,1.63);
      plank.rotation.y=sign*Math.atan2((next-prev)*f,1.44);plank.rotation.z=-sign*.19;
    }
    if(j%2===0){
      for(const sign of [-1,1])stem(ship,v(sign*w*.4,-3.3,z),v(sign*w,.4,z),.17,'#b09a73');
    }
    // The deck has an open hold and a ragged missing section at the impact site.
    if(z> -4&&z<4){
      for(const sign of [-1,1])box(ship,'#a18d68',sign*(w+1.8)/2,.05,z,w-1.8,.22,1.42);
    }else box(ship,j%2?'#9b8765':'#ac9670',0,.05,z,w*1.92,.22,1.42);
    for(const sign of [-1,1])if(j<14||j>17){
      stem(ship,v(sign*w,.3,z),v(sign*w,1.6,z),.08,'#9f9575');
      stem(ship,v(sign*prev,1.6,z-.72),v(sign*next,1.6,z+.72),.10,'#b8a57f');
    }
  }
  box(ship,'#514c42',0,-3.5,0,.7,.6,30);
  for(const x of [-1.85,1.85])box(ship,'#594f40',x,.35,0,.24,.7,7.4);
  for(const z of [-3.7,3.7])box(ship,'#594f40',0,.35,z,3.9,.7,.24);
  // Raised sterncastle, cabin windows and quarterdeck.
  box(ship,'#6f6955',0,1.35,-11.2,7.5,2.5,5.4);
  box(ship,'#b6a07a',0,2.72,-11.2,8.3,.3,5.9);
  for(let i=0;i<5;i++){
    box(ship,'#325d68',-2.9+i*1.45,1.45,-13.95,.95,1.15,.06);
    box(ship,'#c0ac79',-2.9+i*1.45,1.45,-14.02,.075,1.2,.08);
    box(ship,'#c0ac79',-2.9+i*1.45,1.45,-14.02,1,.08,.08);
  }
  for(const x of [-3.75,3.75]){
    box(ship,'#c2aa7d',x,3.2,-11.2,.16,.8,5.7);
    for(const z of [-9.5,-12.5]){
      box(ship,'#46686c',x*1.02,1.4,z,.06,1.1,.9);
      box(ship,'#c3b183',x*1.025,1.4,z,.08,.07,1);
    }
  }
  // Masts, yards and deliberately torn, curved cloth silhouettes.
  const sailMat=material('#c9c3a1');sailMat.side=T.DoubleSide;
  function sail(y,z,w,h,phase){
    const ps=[],ind=[],nx=12,ny=10;
    for(let row=0;row<=ny;row++)for(let col=0;col<=nx;col++){
      const u=col/nx,t=row/ny,tear=row===ny?((col+phase)%4===0?1.8:(col%3)*.3):0;
      ps.push((u-.5)*w*(1-t*.15),y-t*h+tear,z+Math.sin(u*Math.PI)*Math.sin(t*Math.PI)*1.8);
    }
    for(let row=0;row<ny;row++)for(let col=0;col<nx;col++){
      if((col===2||col===3)&&row>6&&phase===1)continue;
      if(col>8&&row>7&&phase===2)continue;
      const a=row*(nx+1)+col,b=a+nx+1;ind.push(a,b,a+1,b,b+1,a+1);
    }
    const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(ps,3));geo.setIndex(ind);geo.computeVertexNormals();
    const m=new T.Mesh(geo,sailMat);m.name='tattered-brig-sail';ship.add(m);
  }
  for(const [z,h,w] of [[6,15,11],[-3,20,14],[-10,12,8]]){
    stem(ship,v(0,.1,z),v(.4,h,z-.6),.22,'#8b795b');
    for(const yy of [h*.56,h*.85])stem(ship,v(-w/2,yy,z),v(w/2,yy,z),.13,'#a3916a');
    sail(h*.85,z,w,h*.25,z===-3?1:2);
    if(z===-3)sail(h*.56,z,12,6,2);
    for(const sign of [-1,1]){
      stem(ship,v(.3,h-.5,z),v(sign*4,.5,z+4),.035,'#829288');
      for(let k=0;k<5;k++)stem(ship,v(sign*(.4+k*.65),h-1-k*2.5,z+k*.7),v(sign*(1.1+k*.65),h-1-k*2.5,z+k*.7),.03,'#829288');
    }
  }
  stem(ship,v(0,-.2,14),v(0,4.5,22),.19,'#a58c63');
  stem(ship,v(0,4.5,22),v(0,14,6),.035,'#8c9d92');
  // A broken mizzen yard and slack rigging make the wreck feel grounded.
  stem(ship,v(-6,.5,-2),v(6,1.2,5),.18,'#8a7c5c');
  for(const sign of [-1,1])for(const z of [-6,0,6]){
    const gun=mesh(ship,new T.CylinderGeometry(.27,.38,2.4,9),'#3c5b5f',sign*4.4,.8,z,1,1,1);gun.rotation.z=Math.PI/2;
    box(ship,'#77674e',sign*3.7,.35,z,1.5,.4,.9);
  }
  const wheel=mesh(ship,new T.TorusGeometry(.75,.09,6,14),'#bca475',0,3.7,-10,1,1,1);
  for(let i=0;i<8;i++){const a=i*Math.PI/4;stem(ship,v(0,3.7,-10),v(Math.sin(a)*.94,3.7+Math.cos(a)*.94,-10),.055,'#bca475');}
  box(ship,'#8e7b56',0,3.2,-10,.20,1.3,.25);
  // Small skull on the mainmast's tattered black pennant.
  const flag=box(ship,'#294d59',1.7,19.1,-3.6,3.3,1.9,.055);flag.rotation.z=-.12;
  rock(ship,'#d5d0af',1.65,19.3,-3.54,.42,.44,.07);
  for(const x of [1.49,1.81])rock(ship,'#294d59',x,19.33,-3.46,.09,.12,.035);
  for(const sign of [-1,1])stem(ship,v(1.13,18.8+sign*.24,-3.5),v(2.16,18.8-sign*.24,-3.5),.055,'#d5d0af');
  // Silt mound under the rolled keel, then fallen timber leading toward the bow.
  rock(root,'#789b95',2,-225,-131,13,2.8,21);
  for(let i=0;i<15;i++){
    const x=8+Math.sin(i*4.7)*10,z=-112-i*2.5,y=trenchFloorAt(x,z);
    const p=box(root,i%2?'#9d916b':'#718778',x,y+.35,z,.34,.26,2+i%4);p.rotation.y=i*1.7;
  }
  // Ship collision uses transformed local parts, leaving the water above the deck free.
  ship.updateWorldMatrix(true,true);
  for(let i=0;i<10;i++){
    const z=-14+i*3,w=halfWidth(z)*.86;
    const b=new T.Box3(v(-w,-3.6,z-1.5),v(w,.2,z+1.5)).applyMatrix4(ship.matrixWorld),c=b.getCenter(v(0,0,0)),s=b.getSize(v(0,0,0));
    solidBuildings.push({x:c.x,z:c.z,w:s.x/2,d:s.z/2,top:b.max.y,bottom:b.min.y});
  }
  // Monumental plate reefs, fan corals and antler colonies: three distinct silhouettes.
  const corals=[];
  const plateMat=material('#b490ef').clone();plateMat.color.set('#ffffff');plateMat.vertexColors=true;plateMat.side=T.DoubleSide;plateMat.onBeforeCompile=material('#b490ef').onBeforeCompile;
  // Ruffled, cupped living edges. Shared geometry keeps colonies inexpensive.
  const plateGeos=Array.from({length:3},(_,phase)=>{
    const p=[],c=[],ix=[],rings=7,sides=48,inner=new T.Color('#837ba7'),edge=new T.Color('#e9b9ce');
    for(let row=0;row<=rings;row++)for(let k=0;k<=sides;k++){
      const a=k/sides*Math.PI*2,u=row/rings;
      const r=u*(1+.11*Math.sin(a*3+phase)+.055*Math.sin(a*7-phase)+.03*Math.sin(a*13));
      p.push(Math.cos(a)*r,Math.pow(u,1.7)*(.10+.055*Math.sin(a*5+phase))-.09,Math.sin(a)*r*.83);
      const color=inner.clone().lerp(edge,Math.pow(u,5));c.push(color.r,color.g,color.b);
    }
    for(let row=0;row<rings;row++)for(let k=0;k<sides;k++){const a=row*(sides+1)+k,b=a+sides+1;ix.push(a,b,a+1,b,b+1,a+1);}
    const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(p,3));geo.setAttribute('color',new T.Float32BufferAttribute(c,3));geo.setIndex(ix);geo.computeVertexNormals();return geo;
  });
  function colony(x,z,size,type,index){
    const y=trenchFloorAt(x,z),g=group(x,y,z,'giant-trench-coral');g.userData={type,height:size,ground:y};corals.push(g);
    rock(g,'#4d8486',0,-.4,0,size*.43,size*.17,size*.38);
    if(type==='plates'){
      stem(g,v(0,0,0),v(0,size,0),size*.09,'#668b94');
      for(let k=0;k<7;k++){
        const a=k*2.4,r=size*(.3+.08*Math.sin(k)),yy=size*(.18+k*.12);
        const p=new T.Mesh(plateGeos[k%3],plateMat);p.position.set(Math.sin(a)*size*.17,yy,Math.cos(a)*size*.15);p.scale.setScalar(r);p.rotation.set(.08,a,Math.sin(k)*.13);g.add(p);
      }
    }else if(type==='fan'){
      // Dense radial lattice creates a broad organic fan, not a handful of wires.
      const fanPoint=(k,t)=>{const a=-1.28+k*2.56/30+.035*Math.sin(t*7+k);return v(Math.sin(a)*size*.72*t,Math.cos(a)*size*t*(.96+.05*Math.sin(k*2)),Math.sin(a*2+t*4)*size*.085*t);};
      for(let k=0;k<=30;k++){
        for(let j=0;j<8;j++){
          const a=fanPoint(k,j/8),b=fanPoint(k,(j+1)/8);
          stem(g,a,b,size*(.012-j*.001),'#dc8da6');
          if(k<30&&j>2)stem(g,b,fanPoint(k+1,(j+.65)/8),size*.0035,'#ff79bf');
          if(j>4&&k%2===0){const tip=b.clone().add(v(Math.sin(k)*size*.035,size*.055,Math.cos(k)*size*.018));stem(g,b,tip,size*.004,'#efb4c3');}
        }
      }
      g.rotation.y=index*.7;
    }else{
      for(let k=0;k<7;k++){
        const a=k*2.4,b=v(Math.cos(a)*size*.25,size*(.40+(k%3)*.12),Math.sin(a)*size*.25);
        stem(g,v(0,0,0),b,size*.045,'#479caa');
        for(let j=0;j<3;j++){
          const end=b.clone().add(v(Math.cos(a+j)*size*.20,size*.30,Math.sin(a+j)*size*.2));stem(g,b,end,size*.028,'#5be1e0');
          for(let q=0;q<2;q++){const tip=end.clone().add(v((q-.5)*size*.17,size*.13,.1*size));stem(g,end,tip,size*.016,'#9ae5d0');rock(g,'#b3ecd6',...tip.toArray(),size*.027,size*.04,size*.027);}
        }
      }
    }
    return g;
  }
  [[-20,-110,15,'antlers'],[23,-118,20,'plates'],[-21,-136,24,'fan'],[17,-145,15,'antlers'],[-8,-157,13,'plates'],[-15,-83,9,'plates'],[17,-92,12,'fan'],[8,-64,5,'antlers']].forEach((p,i)=>colony(...p,i));
  for(let i=0;i<30;i++){
    const z=-95-(i%10)*6,sign=i%2?1:-1,x=sign*(14+(i%4)*2.1),y=trenchFloorAt(x,z);
    if(!Number.isFinite(y))continue;
    rock(root,i%3?'#789fa1':'#ad93b8',x,y+.4,z,2+(i%3),1.2,2.4);
    if(i%3===0)colony(x,z,3+i%5,i%2?'plates':'antlers',i);
  }
  // Local teal/lavender light makes the giant reefs legible in the deep blue water.
  for(const [x,y,z,color,power] of [[-18,-205,-125,'#67d9d9',1600],[20,-207,-135,'#c6a2ef',1400],[0,-199,-122,'#b9dfd2',1100]]){
    const l=new T.PointLight(color,power,65,2);l.position.set(x,y,z);root.add(l);
  }
  function contains(p,margin=0){
    const s=trenchSection(p.z);if(!s||p.z< -171+margin)return false;
    return Math.abs(p.x-s.center)<s.half-margin && p.y>trenchFloorAt(p.x,p.z)+margin && p.y<4;
  }
  return {ship,corals,ground,contains,floorAt:trenchFloorAt,sectionAt:trenchSection,minY:-225,maxZ:-26,minZ:-172};
}
