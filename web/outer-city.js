// Dense city beyond the harbour, assembled from the same finished 120% buildings.
// Visual instances are batched; separate waterline footings keep navigation from
// mistaking a city-wide InstancedMesh bounding box for one solid harbour-sized wall.
import { moveHarborBoundary } from './harbor-boundary-shape.js';
export function createOuterCity({T,root,sources,make,lagoonExpansion=1}) {
  const visuals=new T.Group();visuals.name='outer-city-visuals';visuals.userData.noSailBlock=true;root.add(visuals);
  const solids=new T.Group();solids.name='outer-city-waterline-solids';root.add(solids);
  const buckets=new Map(),placements=[],dummy=new T.Object3D(),local=new T.Matrix4();
  const templates=sources.slice(0,6).map(source=>{
    source.updateWorldMatrix(true,true);const inverse=source.matrixWorld.clone().invert(),parts=[];
    source.traverse(m=>{
      if(!m.isMesh)return;
      for(let p=m;p&&p!==source;p=p.parent)if(!p.visible)return;
      const base=new T.Matrix4().multiplyMatrices(inverse,m.matrixWorld);
      if(m.isInstancedMesh){for(let i=0;i<m.count;i++){m.getMatrixAt(i,local);parts.push({geometry:m.geometry,material:m.material,matrix:base.clone().multiply(local)});}}
      else parts.push({geometry:m.geometry,material:m.material,matrix:base});
    });return parts;
  });
  function add(geometry,material,matrix){
    const key=geometry.uuid+material.uuid;
    if(!buckets.has(key))buckets.set(key,{geometry,material,matrices:[]});
    buckets.get(key).matrices.push(matrix);
  }
  const cube=new T.BoxGeometry(1,1,1),baseMat=make('#779e98',{},true);
  const collisionMat=new T.MeshBasicMaterial();collisionMat.visible=false;
  // A deterministic urban fabric: staggered blocks, occasional cross streets,
  // low foreground roofs and taller groups at the rear. No single exposed ring.
  for(let row=-16;row<=16;row++)for(let col=-16;col<=16;col++){
    const hash=Math.abs(Math.sin(col*127.1+row*311.7)*43758.5453)%1;
    let x=col*13+(row%2)*5.8+Math.sin(row*1.7+col)*1.3;
    let z=row*13.5-5+Math.cos(col*1.4+row)*1.2;
    // Leave the expanded inner lagoon untouched. The northern sea trench is
    // underwater; the city above it may continue behind the northern shoulders.
    if((x/(83*lagoonExpansion))**2+((z+5)/(86*lagoonExpansion))**2<1)continue;
    // Clear the entire former exit segment, including the city directly behind it.
    if(z< -66*lagoonExpansion&&Math.abs(x-49.56*lagoonExpansion)<30)continue;
    if(Math.abs(x)>204||Math.abs(z+5)>216)continue;
    const ring=Math.hypot(x/(83*lagoonExpansion),(z+5)/(86*lagoonExpansion)),front=z>20||x<-35;
    const source=(col+row)%4===0?1+Math.floor(hash*5):0;
    let lift=(front?1:8)+hash*9+Math.sin(col*.61+row*.83)*3;
    if(ring<1.4&&front)lift-=5;
    const yaw=Math.sin(row*.7+col*.4)*.12;
    const lean=(Math.abs(col*3+row)%13===0?1:0)*(.12+hash*.12)*(col%2?1:-1);
    [x,z]=moveHarborBoundary(x,z);
    dummy.position.set(x,lift,z);dummy.rotation.set(0,yaw,lean);dummy.scale.setScalar(1.2);dummy.updateMatrix();
    for(const part of templates[source])add(part.geometry,part.material,new T.Matrix4().multiplyMatrices(dummy.matrix,part.matrix));
    placements.push({x,z,source,lift,lean,scale:1.2});
    dummy.position.set(x,-3,z);dummy.rotation.set(0,yaw,0);dummy.scale.set(8.6,11,8.4);dummy.updateMatrix();add(cube,baseMat,dummy.matrix.clone());
    const solid=new T.Mesh(cube,collisionMat);solid.position.copy(dummy.position);solid.rotation.copy(dummy.rotation);solid.scale.copy(dummy.scale);solids.add(solid);
    // Broad low warehouse roofs punctuate the tall residential rhythm.
    if((col+2*row)%7===0){
      dummy.position.set(x+4,3.1,z+3);dummy.rotation.set(0,yaw,0);dummy.scale.set(12,.6,9);dummy.updateMatrix();add(cube,baseMat,dummy.matrix.clone());
    }
  }
  for(const {geometry,material,matrices} of buckets.values()){
    const batch=new T.InstancedMesh(geometry,material,matrices.length);
    matrices.forEach((m,i)=>batch.setMatrixAt(i,m));batch.castShadow=true;batch.receiveShadow=true;
    batch.computeBoundingSphere();visuals.add(batch);
  }
  return {visuals,solids,placements,batches:buckets.size};
}
