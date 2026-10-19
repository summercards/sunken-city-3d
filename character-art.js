// Procedural character source. +Z faces forward; gameplay owns the root and shoulders/hips.
export function refineCharacter(T, p) {
  const mat=(color,roughness=.72,metalness=0)=>new T.MeshStandardMaterial({color,roughness,metalness});
  const cloth=mat('#ed934d'),dark=mat('#244757'),skin=mat('#ffdbb8'),gold=mat('#edc064'),rubber=mat('#18333e');
  const hairMat=mat('#55372f'),hairLight=mat('#79503a'),lip=mat('#bd786f');
  const sphere=new T.SphereGeometry(1,24,16);
  function oval(parent,m,x,y,z,sx,sy,sz){const o=new T.Mesh(sphere,m);o.position.set(x,y,z);o.scale.set(sx,sy,sz);parent.add(o);return o;}
  function joint(parent,name,x,y,z){const o=new T.Group();o.name=name;o.position.set(x,y,z);parent.add(o);return o;}
  function capsule(parent,m,r,length,x,y,z){const o=new T.Mesh(new T.CapsuleGeometry(r,length,6,16),m);o.position.set(x,y,z);parent.add(o);return o;}
  p.torsoMesh.geometry.dispose();p.torsoMesh.geometry=new T.SphereGeometry(1,28,20);p.torsoMesh.scale.set(.218,.33,.153);p.torsoMesh.material=cloth;
  // Remove the old cone outline as it no longer matches the tailored silhouette.
  p.torsoMesh.clear();p.headMesh.geometry.dispose();p.headMesh.geometry=new T.SphereGeometry(.21,32,24);p.headMesh.material=skin;p.headMesh.scale.set(.96,1,.97);
  const head=joint(p.explorerBodyPivot,'head-look',0,.98,0);p.explorerBodyPivot.remove(p.headMesh);head.add(p.headMesh);p.headMesh.position.y=0;
  const hair=new T.Mesh(new T.SphereGeometry(.214,32,20,0,Math.PI*2,0,1.22),hairMat);head.add(hair);
  // Side-swept fringe and a secured side braid remain readable with the diving mask.
  const fringe=oval(head,hairMat,-.065,.104,.15,.145,.055,.064);fringe.rotation.z=-.3;
  oval(head,hairMat,-.176,.018,.075,.049,.135,.081);
  oval(head,hairMat,.181,.015,.025,.036,.12,.087);
  const braid=joint(head,'secured-side-braid',-.205,-.07,-.065);
  for(let i=0;i<5;i++){
    const x=(i%2?1:-1)*.016-i*.008;
    const lock=oval(braid,i%2?hairMat:hairLight,x,-i*.052,0,.047-i*.004,.044,.04-i*.003);lock.rotation.z=(i%2?1:-1)*.35;
  }
  oval(braid,gold,-.034,-.239,0,.031,.018,.029);
  oval(braid,hairMat,-.039,-.276,0,.025,.035,.025);
  for(const s of [-1,1]){oval(head,skin,s*.202,-.012,0,.038,.056,.035);oval(head,rubber,s*.072,.015,.192,.023,.033,.014);oval(head,mat('#fff7dc'),s*.067,.025,.204,.007,.01,.004);oval(head,mat('#e99b83'),s*.115,-.056,.173,.036,.017,.008);}
  for(const side of [-1,1]){
    const brow=oval(head,hairMat,side*.075,.067,.184,.037,.008,.009);brow.rotation.z=-side*.12;
    const lash=oval(head,hairMat,side*.09,.033,.193,.025,.007,.009);lash.rotation.z=side*.35;
  }
  oval(head,skin,0,-.025,.203,.027,.03,.025);
  oval(head,lip,0,-.088,.185,.031,.012,.01);
  for(const hat of [p.hatBrim,p.hatCrown]){hat.geometry.dispose();}
  p.hatBrim.geometry=new T.CylinderGeometry(.33,.34,.045,40);p.hatCrown.geometry=new T.CylinderGeometry(.18,.215,.16,32);
  const elbows=[],knees=[],ankles=[];
  for(const [i,s] of [-1,1].entries()){
    const arm=i?p.rightArmPivot:p.leftArmPivot,leg=i?p.rightLegPivot:p.leftLegPivot;
    // Existing tool socket stays under the shoulder; only its visual mesh is replaced.
    const oldArm=arm.children.find(o=>o.isMesh);arm.remove(oldArm);oldArm.geometry.dispose();
    capsule(arm,cloth,.065,.105,0,-.075,0);
    const elbow=joint(arm,`elbow-${i}`,0,-.16,0);elbows.push(elbow);
    capsule(elbow,cloth,.055,.08,0,-.055,0);oval(elbow,skin,0,-.145,.008,.058,.068,.045);
    const oldLeg=leg.children.find(o=>o.isMesh);leg.remove(oldLeg);oldLeg.geometry.dispose();
    capsule(leg,dark,.068,.045,0,-.045,0);
    const knee=joint(leg,`knee-${i}`,0,-.12,0);knees.push(knee);capsule(knee,dark,.055,.04,0,-.04,0);
    const ankle=joint(knee,`ankle-${i}`,0,-.12,0);ankles.push(ankle);oval(ankle,rubber,0,.015,.035,.066,.046,.105);
    capsule(p.explorerBodyPivot,dark,.019,.36,s*.14,.57,.133);
    oval(p.explorerBodyPivot,gold,s*.14,.62,.156,.034,.033,.012);
  }
  capsule(p.explorerBodyPivot,gold,.012,.32,0,.55,.162);
  oval(p.explorerBodyPivot,dark,0,.3,0,.21,.065,.154);
  const gear=joint(p.explorerBodyPivot,'diving-equipment',0,0,0);gear.visible=false;
  capsule(gear,mat('#c4d5cb',.35,.35),.112,.32,0,.56,-.205);
  for(const y of [.43,.68])oval(gear,dark,0,y,-.21,.118,.026,.115);
  capsule(gear,gold,.025,.055,0,.86,-.21);
  const mask=joint(head,'dive-mask',0,0,0);mask.visible=false;
  oval(mask,rubber,0,.013,.19,.204,.102,.06);
  const glass=mat('#a3e6df',.12,.25);glass.transparent=true;glass.opacity=.65;glass.depthWrite=false;
  for(const s of [-1,1]){oval(mask,gold,s*.087,.018,.233,.084,.073,.021);oval(mask,glass,s*.087,.022,.25,.071,.059,.014);}
  const regulator=oval(head,rubber,0,-.095,.226,.044,.037,.035);regulator.visible=false;
  const hose=new T.Mesh(new T.TubeGeometry(new T.CatmullRomCurve3([new T.Vector3(0,.885,.25),new T.Vector3(.27,.8,.22),new T.Vector3(.32,.61,-.12),new T.Vector3(.06,.84,-.22)]),24,.015,8,false),rubber);gear.add(hose);
  const fins=ankles.map((ankle,i)=>{
    const f=joint(ankle,`fin-${i}`,0,0,.045);f.visible=false;
    const shape=new T.Shape();shape.moveTo(-.06,0);shape.lineTo(.06,0);shape.quadraticCurveTo(.1,.17,.13,.34);shape.quadraticCurveTo(0,.39,-.13,.34);shape.quadraticCurveTo(-.1,.17,-.06,0);
    const g=new T.ExtrudeGeometry(shape,{depth:.018,bevelEnabled:true,bevelSegments:2,steps:1,bevelSize:.009,bevelThickness:.006,curveSegments:10});g.rotateX(Math.PI/2);
    const blade=new T.Mesh(g,gold);f.add(blade);
    for(const s of [-1,1]){const rib=capsule(f,rubber,.009,.25,s*.063,-.012,.18);rib.rotation.x=Math.PI/2;}
    return f;
  });
  return {head,elbows,knees,ankles,gear,mask,regulator,fins};
}

export function createSwimAnimation(T,p){
  const r=p.detail,body=p.explorerBodyPivot;
  const nodes=[body,r.head,p.leftArmPivot,p.rightArmPivot,p.leftLegPivot,p.rightLegPivot,...r.elbows,...r.knees,...r.ankles];
  let saved=[],cycle=0,effort=0;
  const ease=(a,b,dt)=>T.MathUtils.lerp(a,b,1-Math.exp(-dt*5));
  function pose(o,x,y,z,dt){o.rotation.x=ease(o.rotation.x,x,dt);o.rotation.y=ease(o.rotation.y,y,dt);o.rotation.z=ease(o.rotation.z,z,dt);}
  return {
    start(){saved=nodes.map(o=>({rotation:o.rotation.clone(),position:o.position.clone()}));cycle=0;effort=0;[r.gear,r.mask,r.regulator,...r.fins].forEach(o=>o.visible=true);},
    finish(){nodes.forEach((o,i)=>{o.rotation.copy(saved[i].rotation);o.position.copy(saved[i].position);});[r.gear,r.mask,r.regulator,...r.fins].forEach(o=>o.visible=false);},
    update(dt,velocity,phase,search,turn){
      const horizontal=Math.hypot(velocity.x,velocity.z),moving=T.MathUtils.clamp(horizontal/3.8,0,1);
      effort=ease(effort,moving,dt);cycle+=dt*(2.1+effort*2.5);
      const vertical=phase==='enter'?-1:phase==='exit'?1:T.MathUtils.clamp(velocity.y/2.66,-1,1);
      // Head leads +Z: positive pitch lays the torso forward. Legs trail behind.
      const tilt=phase==='enter'?1.95:phase==='exit'?.25:.4+effort*.95-vertical*.65;
      pose(body,tilt,0,T.MathUtils.clamp(-turn*.16,-.22,.22)+Math.sin(cycle)*.025,dt);
      body.position.y=ease(body.position.y,Math.sin(cycle*.55)*.025,dt);
      pose(r.head,-.15-effort*.4,Math.sin(cycle*.35)*.035,0,dt);
      for(let i=0;i<2;i++){
        const side=i?1:-1,wave=Math.sin(cycle+i*Math.PI),arm=i?p.rightArmPivot:p.leftArmPivot,leg=i?p.rightLegPivot:p.leftLegPivot;
        // Quiet sculling at rest, bent elbows held ahead when cruising; alternating fin beats.
        pose(arm,search?-1.1+wave*.12:-.35-effort*.7+wave*.12*(1-effort),0,side*(.24+(1-effort)*.16+Math.cos(cycle)*.07),dt);
        pose(r.elbows[i],search?-.9:-.65-effort*.35,0,0,dt);
        pose(leg,wave*(.13+effort*.27)+.08,0,side*.08,dt);
        pose(r.knees[i],.18+Math.max(0,-wave)*(.22+effort*.32),0,0,dt);
        pose(r.ankles[i],1.05+Math.sin(cycle+i*Math.PI-.65)*(.12+effort*.16),0,0,dt);
      }
    },
    mouthPosition(target){r.regulator.getWorldPosition(target);return target;}
  };
}
