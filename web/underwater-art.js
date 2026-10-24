import { createUnderwaterNeighborhood } from './underwater-neighborhood.js';
import { createUnderwaterOptics } from './underwater-optics.js';
import { createNorthTrench } from './north-trench.js';
// Art-directed underwater canyon: an independent map with the surface city’s cream masonry and curved bays.
export function createUnderwaterArt({ THREE: T, scene, worldGroup, waterLevel }) {
  const root = new T.Group(); root.name = 'underwater-city'; root.visible = false; scene.add(root);
  const time = { value: 0 }, depth = { value: 10 }, materials = new Map(), swaying = [], schools = [], buildings = [], solidBuildings = [];
  let seed = 71;
  const random = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
  const boxGeo = new T.BoxGeometry(1, 1, 1), rockGeo = new T.IcosahedronGeometry(1, 1);
  const stemGeo = new T.CylinderGeometry(1, 1, 1, 7);
  function material(color) {
    if (materials.has(color)) return materials.get(color);
    const m = new T.MeshStandardMaterial({ color, roughness: .58, metalness: .06, flatShading: true });
    if(['#ffc55c','#f19c4a','#ff79bf','#b490ef','#5be1e0','#55df87'].includes(color)){m.emissive.set(color);m.emissiveIntensity=.35;}
    m.onBeforeCompile = shader => {
      shader.uniforms.reefTime = time;shader.uniforms.diveDepth=depth;
      shader.vertexShader = 'varying vec3 reefWorld; varying vec4 reefClip;\n' + shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvec4 reefP=vec4(position,1.0);\n#ifdef USE_INSTANCING\nreefP=instanceMatrix*reefP;\n#endif\nreefWorld=(modelMatrix*reefP).xyz;reefClip=projectionMatrix*viewMatrix*vec4(reefWorld,1.);');
      shader.fragmentShader = 'varying vec3 reefWorld; varying vec4 reefClip; uniform float reefTime;uniform float diveDepth;\n' + shader.fragmentShader.replace('#include <opaque_fragment>', `
        vec2 p=reefWorld.xz*.85+reefWorld.y*.2;
        p+=vec2(sin(p.y+reefTime*.4),cos(p.x-reefTime*.32))*.38;
        float net=abs(sin(p.x*2.1+sin(p.y*1.8)+reefTime*.48)+sin(p.y*2.2-reefTime*.37));
        float light=(1.-smoothstep(.035,.16,net))*.24;
        float litTop=max(inverseTransformDirection(normal,viewMatrix).y,0.);
        float shallow=1.-smoothstep(12.,55.,-reefWorld.y);
        outgoingLight+=vec3(.5,.65,.5)*pow(max(0.,sin(p.x*2.1+reefTime*.65)*cos(p.y*1.9-reefTime*.4)),18.)*litTop*shallow*.16;
        outgoingLight+=diffuseColor.rgb*vec3(.45,1.,.88)*light*mix(1.,.18,smoothstep(65.,170.,diveDepth));
        #include <opaque_fragment>`).replace('#include <fog_fragment>',`
        float d=clamp((diveDepth-8.)/72.,0.,1.);
        vec3 top=mix(vec3(.12,.91,.87),vec3(.025,.28,.49),d);
        vec3 bottom=mix(vec3(.025,.36,.62),vec3(.008,.07,.20),d);
        float screenY=clamp(reefClip.y/reefClip.w*.5+.5,0.,1.);
        vec3 waterColor=mix(bottom,top,pow(screenY,.8));
        float density=mix(.026,.012,smoothstep(65.,210.,diveDepth));
        float fogAmount=1.-exp(-pow(vFogDepth*density,1.8));
        gl_FragColor.rgb=mix(gl_FragColor.rgb,waterColor,clamp(fogAmount,0.,1.));
      `);
    };
    materials.set(color, m); return m;
  }
  function mesh(p, geo, color, x, y, z, sx, sy, sz) {
    const o = new T.Mesh(geo, material(color)); o.position.set(x,y,z); o.scale.set(sx,sy,sz);
    o.castShadow = geo===rockGeo||geo===boxGeo; o.receiveShadow = true; p.add(o); return o;
  }
  const box = (p,c,x,y,z,w,h,d) => mesh(p,boxGeo,c,x,y,z,w,h,d);
  const rock = (p,c,x,y,z,w,h,d) => mesh(p,rockGeo,c,x,y,z,w,h,d);
  function group(x,y,z,name) { const g=new T.Group(); g.position.set(x,y,z); g.name=name; root.add(g); return g; }
  function stem(p,a,b,r,c) {
    const delta=b.clone().sub(a), o=mesh(p,stemGeo,c,...a.clone().add(b).multiplyScalar(.5).toArray(),r,delta.length(),r);
    o.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),delta.normalize()); return o;
  }
  function boundsAt(y){const d=T.MathUtils.clamp((-y-6)/70,0,1);return {x:30-16*d,z:49-15*d};}
  function insideBasin(p,margin=0){
    const b=boundsAt(p.y);
    const oldBasin=p.y> -75+margin && (p.x/(b.x-margin))**2+(p.z/(b.z-margin))**2<1;
    return oldBasin||trench.contains(p,margin);
  }
  // One continuous rock bowl from surface to seabed. There are no gaps beneath isolated platforms.
  const wallPositions=[],wallIndices=[],segments=48,layers=11;
  for(let row=0;row<=layers;row++){
    const y=4-row*80/layers,b=boundsAt(y);
    for(let k=0;k<=segments;k++){
      const a=k/segments*Math.PI*2,ripple=1+Math.sin(k*.93+row*.7)*.024;
      wallPositions.push(Math.cos(a)*(b.x+1)*ripple,y,Math.sin(a)*(b.z+1)*ripple);
    }
  }
  for(let row=0;row<layers;row++)for(let k=0;k<segments;k++){
    // Open the north-facing sector all the way down to the original seabed.
    const angle=(k+.5)/segments*Math.PI*2;
    if(Math.sin(angle)<-.72)continue;
    const a=row*(segments+1)+k,b=a+segments+1;wallIndices.push(a,b,a+1,b,b+1,a+1);
  }
  const bowlGeo=new T.BufferGeometry();bowlGeo.setAttribute('position',new T.Float32BufferAttribute(wallPositions,3));bowlGeo.setIndex(wallIndices);bowlGeo.computeVertexNormals();
  const bowlMaterial=material('#4b8797').clone();bowlMaterial.onBeforeCompile=material('#4b8797').onBeforeCompile;bowlMaterial.side=T.DoubleSide;
  const bowl=new T.Mesh(bowlGeo,bowlMaterial);bowl.name='continuous-tapered-rock-basin';bowl.receiveShadow=true;root.add(bowl);
  // Overlapping strata break the silhouette while remaining attached to the continuous rock wall.
  for(let row=0;row<8;row++)for(let k=0;k<24;k++){
    const y=-3-row*10,a=k/24*Math.PI*2,b=boundsAt(y),x=Math.cos(a)*(b.x+3),z=Math.sin(a)*(b.z+3);
    if(Math.sin(a)<-.70)continue;
    const r=rock(root,row%2?'#4e8295':'#608f9c',x,y,z,5.5,6.8,7.2);r.rotation.y=-a;
  }
  // The floor is 75 metres below the entry. Staggered shelves, not a flat visible bottom.
  // Stop the old floor at the northern threshold; an infinite plane would plug
  // the new canyon at -75 m even if the swim bounds allowed the deeper descent.
  box(root,'#407b88',0,-76,16,90,2,84);
  const terraces=[
    [-12,2,6,7,-18], [13,-7,7,7,-31], [-12,-20,7,8,-46], [13,12,7,7,-59],
    [-17,25,7,7,-25], [18,-30,8,7,-40], [-14,34,8,8,-62], [0,-27,8,7,-74]
  ];
  const ledgeColors=['#8aaca0','#679cb0','#9d98b3','#67a6a7'];
  terraces.forEach(([x,z,w,d,y],i)=>{
    const g=group(x,y,z,'reef-terrace-'+i);
    rock(g,ledgeColors[i%4],0,-2.5,0,w,3.2,d);
    rock(g,'#b0c9a6',0,.05,0,w*.95,.45,d*.92);
    const bottom=-76,baseHeight=y-bottom;
    rock(g,'#477e91',x<0?-2:2,-baseHeight*.5-1,0,w*1.03,baseHeight*.56,d*1.04);
    // A broad backfill plugs each shelf into the perimeter rather than leaving it hovering.
    const b=boundsAt(y),wallX=Math.sign(x||1)*b.x*Math.sqrt(Math.max(.1,1-(z/b.z)**2));
    const span=Math.abs(wallX-x);
    rock(g,'#527f90',(wallX-x)*.55,-baseHeight*.5,0,Math.max(w,span*.75),baseHeight*.55,d*.85);
    for(let j=0;j<6;j++)rock(g,j%2?'#7698b1':'#8ab7ac',(random()-.5)*w,random()*.5,(random()-.5)*d,.8+random(),.3+random()*.5,.6+random());
  });
  // Uneven sand pockets only emerge when the diver reaches the lower water column.
  for(let i=0;i<24;i++){
    const x=(random()-.5)*48,z=(random()-.5)*80,h=1+random()*3.5;
    rock(root,i%3?'#6fa8a1':'#929aba',x,-75+h*.4,z,3+random()*4,h,3+random()*4);
  }
  const neighborhood=createUnderwaterNeighborhood({T,root,group,box,rock,mesh,stem,buildings,solidBuildings});
  const trench=createNorthTrench({T,root,group,box,rock,mesh,stem,material,solidBuildings});
  function coral(x,y,z,index,scale=1) {
    const g=group(x,y,z,'reef-coral');g.scale.setScalar(scale);
    const colors=['#ff79bf','#b490ef','#5be1e0','#ffb64f'];const c=colors[Math.floor(index/3)%4];
    rock(g,'#6c9185',0,.1,0,.75,.25,.65);
    if(index%3===0){
      // Rounded cauliflower/boulder colonies: large solid colour masses, not thin wire branches.
      for(let j=0;j<11;j++){const a=j*2.4,r=.25+random()*.65;rock(g,c,Math.cos(a)*r,.45+random()*.85,Math.sin(a)*r,.43+random()*.28,.4+random()*.25,.43+random()*.22);}
    }else if(index%3===1){
      for(let j=0;j<7;j++) {
        const a=j*2.4,h=1+random()*1.3,b=new T.Vector3(Math.cos(a)*.65,h,Math.sin(a)*.65);
        stem(g,new T.Vector3(0,.15,0),b,.18,c);
        for(let k=0;k<3;k++){const end=b.clone().add(new T.Vector3(Math.cos(a+k)*.42,.4+k*.1,Math.sin(a+k)*.42));stem(g,b.clone().multiplyScalar(.65),end,.135,c);rock(g,c,...end.toArray(),.16,.22,.16);}
      }
    }else{
      // Stacked plate colonies provide broad, full silhouettes between branching corals.
      for(let j=0;j<7;j++){const a=j*2.4,h=.3+j*.2;rock(g,c,Math.cos(a)*.4,h,Math.sin(a)*.4,.85-j*.055,.16,.7-j*.035);}
    }
    swaying.push({g,phase:index,amp:.025});
  }
  // Plant along footings and ledges, leaving the centre open to read the diver silhouette.
  for(let i=0;i<210;i++) {
    const site=terraces[i%terraces.length],x=site[0]+(random()-.5)*site[2]*1.9,z=site[1]+(random()-.5)*site[3]*1.9;
    coral(x,site[4]+.45,z,i,.8+random()*1.05);
  }
  neighborhood.coralSites.forEach(([x,y,z],i)=>coral(x,y,z,230+i,.45+random()*.35));
  for(let i=0;i<55;i++) {
    const site=terraces[i%terraces.length],x=site[0]+(random()-.5)*site[2]*1.6,z=site[1]+(random()-.5)*site[3]*1.5,y=site[4]+.4;
    const g=group(x,y,z,'ribbon-kelp'),h=1.8+random()*4;
    for(let j=0;j<5;j++) {
      const geometry=new T.PlaneGeometry(.22,h*(.65+j*.08),1,10),p=geometry.attributes.position;
      for(let k=0;k<p.count;k++)p.setX(k,p.getX(k)+Math.sin(p.getY(k)*2+j)*.16);
      geometry.computeVertexNormals();
      const blade=mesh(g,geometry,j%2?'#a0e77d':'#55df87',(j-2)*.17,h*.42,0,1,1,1);
      blade.material.side=T.DoubleSide;blade.rotation.y=j*1.1;blade.rotation.z=(j-2)*.12;
    }
    swaying.push({g,phase:i*.7,amp:.1});
  }
  for(const [x,z,w,d,y] of terraces){
    for(let k=0;k<4;k++){
      const xx=x+(random()-.5)*w,zz=z+(random()-.5)*d;
      for(let j=0;j<4;j++){
        const h=.7+random()*1.2;
        mesh(root,new T.CylinderGeometry(.16,.23,h,8,1,true),'#ffb166',xx+j*.28,y+h/2+.5,zz,1,1,1);
        mesh(root,new T.TorusGeometry(.16,.04,5,8),'#ffe49c',xx+j*.28,y+h+.5,zz,1,1,1).rotation.x=Math.PI/2;
      }
      const plate=rock(root,k%2?'#b295e4':'#f08dc1',xx-1,y+.5,zz+1,1.1,.15,.8);plate.rotation.z=.12;
    }
  }
  // Fish use real circuit paths, cohesive school centres and articulated tails.
  const fishGeometry=new T.SphereGeometry(1,9,6),tailGeometry=new T.ConeGeometry(.22,.4,3);
  for(let school=0;school<7;school++) {
    const center=new T.Vector3(-5+(school%2)*10,-13-school*8,-16+(school%4)*11),members=[];
    for(let i=0;i<18;i++) {
      const g=new T.Group();root.add(g);
      const c=['#ffc55c','#f19c4a','#66dcf2','#cd8fea'][school%4];mesh(g,fishGeometry,c,0,0,0,.28,.13,.09);
      const tail=mesh(g,tailGeometry,c,-.32,0,0,1,1,.6);tail.rotation.z=Math.PI/2;
      mesh(g,fishGeometry,'#112e35',.19,.035,.075,.025,.025,.018);
      mesh(g,fishGeometry,'#fff2cc',.08,.09,0,.12,.065,.03);
      const size=.65+random()*.75;g.scale.setScalar(size);
      members.push({g,tail,phase:random()*6.28,offset:new T.Vector3((random()-.5)*5,(random()-.5)*2,(random()-.5)*4)});
    }
    schools.push({center,members,phase:school*1.7});
  }
  const optics=createUnderwaterOptics({THREE:T,scene,root,waterLevel,time});
  // Soft-edged light volumes; cross-sectional alpha removes hard cone silhouettes.
  const beams=[];
  for(let i=0;i<9;i++) {
    const geo=new T.PlaneGeometry(3.5+(i%3),60);
    const m=new T.ShaderMaterial({transparent:true,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,uniforms:{t:time,phase:{value:i}},vertexShader:'varying vec2 v;void main(){v=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',fragmentShader:`varying vec2 v;uniform float t,phase;void main(){float edge=pow(max(0.,sin(v.x*3.14159)),3.);float end=smoothstep(0.,.35,v.y)*(1.-smoothstep(.92,1.,v.y));float flow=.75+.25*sin(v.y*16.+t*.45+phase);gl_FragColor=vec4(.58,.88,.74,edge*end*flow*.045);}`});
    const beam=new T.Mesh(geo,m);beam.position.set(-20+i*5,-28,-20+(i%3)*15);beam.rotation.z=-.16;root.add(beam);beams.push(beam);
  }
  const particleGeo=new T.BufferGeometry(),pts=new Float32Array(540);
  for(let i=0;i<180;i++){pts[i*3]=-35+random()*65;pts[i*3+1]=-75+random()*75;pts[i*3+2]=-35+random()*65;}
  particleGeo.setAttribute('position',new T.BufferAttribute(pts,3));
  const motes=new T.Points(particleGeo,new T.ShaderMaterial({transparent:true,depthWrite:false,uniforms:{},vertexShader:'void main(){vec4 p=modelViewMatrix*vec4(position,1.);gl_Position=projectionMatrix*p;gl_PointSize=clamp(23./-p.z,1.,4.);}',fragmentShader:'void main(){float r=length(gl_PointCoord-.5);if(r>.5)discard;gl_FragColor=vec4(.7,1.,.88,(1.-r*2.)*.32);}'}));root.add(motes);
  const bubbleCount=96,bubbleDummy=new T.Object3D();
  const bubbleMaterial=new T.MeshPhysicalMaterial({color:'#d3fff1',roughness:.1,metalness:.15,transparent:true,opacity:.38,depthWrite:false,clearcoat:1});
  const bubbleMesh=new T.InstancedMesh(new T.SphereGeometry(1,9,7),bubbleMaterial,bubbleCount);bubbleMesh.name='rising-vent-bubbles';bubbleMesh.frustumCulled=false;root.add(bubbleMesh);
  const vents=[[-7,-18,3],[7,-31,-7],[-6,-46,-19],[7,-59,12],[1,-74,-27],[-8,-14,-10]];
  const key=new T.DirectionalLight('#edffe3',3.0);key.position.set(18,24,18);key.castShadow=true;key.shadow.mapSize.set(1024,1024);Object.assign(key.shadow.camera,{left:-46,right:46,top:46,bottom:-46,near:.5,far:150});key.shadow.bias=-.001;key.target.position.set(-9,-40,-6);root.add(key,key.target);
  const ambient=new T.HemisphereLight('#bbffef','#30538b',1.9);root.add(ambient);
  const fill=new T.PointLight('#a1f7ef',55,32,2);root.add(fill);
  const backdrop=new T.Mesh(new T.PlaneGeometry(2,2),new T.ShaderMaterial({depthTest:false,depthWrite:false,uniforms:{depth},vertexShader:'varying vec2 v;void main(){v=uv;gl_Position=vec4(position.xy, .9999,1.);}',fragmentShader:`varying vec2 v;uniform float depth;void main(){
    float d=clamp((depth-8.)/72.,0.,1.);
    vec3 top=mix(vec3(.12,.91,.87),vec3(.025,.28,.49),d);
    vec3 bottom=mix(vec3(.025,.36,.62),vec3(.008,.07,.20),d);
    gl_FragColor=vec4(mix(bottom,top,pow(v.y,.8)),1.);
  }`}));backdrop.frustumCulled=false;backdrop.renderOrder=-100;root.add(backdrop);
  const moving=new Set([...swaying.map(s=>s.g),...schools.flatMap(s=>s.members.map(f=>f.g)),...beams,bubbleMesh]);
  function batch(anchor){
    anchor.updateWorldMatrix(true,true);const inverse=anchor.matrixWorld.clone().invert(),buckets=new Map();
    function visit(o){if(o!==anchor&&moving.has(o))return;
      if(o.isMesh&&!o.material.isShaderMaterial){const key=o.geometry.uuid+o.material.uuid;if(!buckets.has(key))buckets.set(key,[]);buckets.get(key).push(o);}
      o.children.forEach(visit);
    }visit(anchor);
    for(const list of buckets.values())if(list.length>1){
      const inst=new T.InstancedMesh(list[0].geometry,list[0].material,list.length);
      list.forEach((m,i)=>{inst.setMatrixAt(i,new T.Matrix4().multiplyMatrices(inverse,m.matrixWorld));m.parent.remove(m);});
      inst.castShadow=true;inst.receiveShadow=true;inst.computeBoundingSphere();anchor.add(inst);
    }
  }
  batch(root);swaying.forEach(s=>batch(s.g));
  function update(dt,t,camera,diver) {
    for(let i=0;i<bubbleCount;i++){
      const v=vents[i%vents.length],age=(t*.85+i*.71)%13;
      bubbleDummy.position.set(v[0]+Math.sin(t*.8+i)*.17,v[1]+age,v[2]+Math.cos(t*.65+i)*.14);
      bubbleDummy.scale.setScalar(.035+(i%4)*.018+age*.006);bubbleDummy.updateMatrix();bubbleMesh.setMatrixAt(i,bubbleDummy.matrix);
    }bubbleMesh.instanceMatrix.needsUpdate=true;
    time.value=t;depth.value=-diver.position.y;const deep=T.MathUtils.clamp((-diver.position.y-12)/64,0,1);key.intensity=3*(1-deep*.75);ambient.intensity=1.9*(1-deep*.6);fill.position.copy(diver.position).add(new T.Vector3(0,2,3));
    swaying.forEach(({g,phase,amp})=>{g.rotation.z=Math.sin(t*.7+phase)*amp;g.rotation.x=Math.cos(t*.5+phase)*amp*.5;});
    schools.forEach(({center,members,phase})=>members.forEach(({g,tail,offset,phase:p})=>{
      const a=t*.13+phase,rx=6,rz=3;
      g.position.copy(center).add(offset);g.position.x+=Math.cos(a)*rx;g.position.z+=Math.sin(a)*rz;g.position.y+=Math.sin(t*.7+p)*.2;
      g.rotation.y=Math.atan2(-Math.cos(a)*rz,-Math.sin(a)*rx);tail.rotation.y=Math.sin(t*9+p)*.5;
    }));
    beams.forEach(b=>{b.rotation.y=Math.atan2(camera.position.x-b.position.x,camera.position.z-b.position.z);});
    for(let i=0;i<180;i++){pts[i*3+1]+=dt*.18;if(pts[i*3+1]>0)pts[i*3+1]=-75;}particleGeo.attributes.position.needsUpdate=true;
  }
  return {root,update,material,box,rock,schools,terraces,buildings,solidBuildings,boundsAt,insideBasin,optics,bubbleMesh,neighborhood,trench};
}
