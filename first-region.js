// First major region. North is -Z; all five existing harbour destinations stay inside.
// Reuse the district's finished buildings at exactly 120%, with submerged height and
// lean supplying the skyline variation rather than stretching their floor proportions.
import { createOuterCity } from './outer-city.js';
import { moveHarborBoundary } from './harbor-boundary-shape.js';
export function createFirstRegion({ THREE:T, worldGroup, waterDistrict, makePainterlyMat:make }) {
  const root=new T.Group();root.name='first-region-enclosure';worldGroup.add(root);
  const buildings=[],walls=[],mats=new Map(),cube=new T.BoxGeometry(1,1,1);
  const mat=c=>{if(!mats.has(c))mats.set(c,make(c,{},true));return mats.get(c);};
  const box=(p,x,y,z,w,h,d,c)=>{const m=new T.Mesh(cube,mat(c));m.position.set(x,y,z);m.scale.set(w,h,d);m.castShadow=m.receiveShadow=true;p.add(m);return m;};
  const residence=waterDistrict.landmarks.find(g=>g.name==='reference-balcony-residence');
  const round=waterDistrict.landmarks.find(g=>g.name==='reference-round-garden-building');
  const sources=[residence,...waterDistrict.towers,round];
  const expansion=1.18*1.30;
  const expand=([x,z])=>moveHarborBoundary(x*expansion,-5+(z+5)*expansion);
  // A low inner edge, a broken middle band, and occasional taller rear accents.
  // [x,z,source,lift,yaw,leanZ,leanX] — positions are deliberately staggered.
  const layout=[
    [-49,-49,0,8,.16,-.10,0],[-50,-39,2,7,-.12,0,.06],[-52,-29,1,15,.06,.12,0],
    [-48,-19,0,-2,.10,0,0],[-52,-9,4,1,-.10,-.15,.04],[-49,1,2,0,.16,0,0],
    [-51,11,0,3,-.12,.08,0],[-47,21,3,-2,.20,0,0],[-45,31,1,5,-.18,-.20,.04],
    [-39,40,0,-3,-.28,.04,0],[-29,46,2,1,.08,0,.05],[-19,48,4,-1,-.06,.13,0],
    [-9,47,0,-4,.10,0,0],[1,49,1,2,-.16,0,-.08],[11,47,4,-4,.12,-.08,0],
    [21,46,0,5,-.12,.10,0],[31,43,2,3,.20,0,.04],[40,37,4,9,-.35,-.17,.05],
    [47,29,0,7,.12,0,0],[51,19,3,5,-.10,.13,0],[52,9,1,11,.16,-.14,.05],
    [54,-1,0,3,-.12,0,0],[53,-11,4,-2,.10,0,-.10],[56,-21,4,13,-.14,-.16,0],
    [55,-31,0,8,.10,.07,0],[58,-41,1,10,-.08,0,.10],
    // Rear silhouette: clusters of two or three, then a long quieter wall.
    [-59,-43,0,14,.12,-.08,0],[-61,-30,1,18,-.10,.30,0],[-60,-7,0,11,.08,0,.07],
    [-57,15,2,11,-.18,-.12,0],[-34,56,0,5,.12,0,0],[-22,59,1,11,.16,.17,0],
    [8,58,0,7,-.12,0,-.08],[36,53,1,14,-.25,-.32,.06],[62,24,0,15,.14,0,.07],
    [65,8,2,17,-.10,.13,0],[66,-17,0,12,.16,-.12,0],
    // Northwest shoulders; the former northeast bridge and its end buildings are removed.
    [-38,-57,3,3,.15,0,0],[-29,-60,0,6,-.16,-.10,0],[-18,-63,1,8,.08,.08,0]
  ];
  layout.forEach(([x,z,source,lift,yaw,leanZ,leanX],i)=>{
    [x,z]=expand([x,z]);
    const g=sources[source].clone(true);g.name=`boundary-building-${String(i).padStart(2,'0')}`;
    g.position.set(x,lift,z);g.rotation.set(leanX,yaw,leanZ);g.scale.setScalar(1.2);
    g.userData={region:'first',source:sources[source].name,assetScale:1.2};root.add(g);buildings.push(g);
    // A solid waterline footing closes the open floor-frame models at boat height.
    const footing=box(root,x,-2.5,z,8.2,9,8.2,'#719d97');footing.rotation.y=yaw;
    footing.name=`boundary-footing-${i}`;
  });
  const chain=[[-49,-54],[-50,-39],[-52,-29],[-48,-19],[-52,-9],[-49,1],[-51,11],[-47,21],[-45,31],[-39,40],[-29,46],[-19,48],[-9,47],[1,49],[11,47],[21,46],[31,43],[40,37],[47,29],[51,19],[52,9],[54,-1],[53,-11],[56,-21],[55,-31],[58,-41]];
  const expandedChain=chain.map(expand);
  root.userData.sailBounds={
    minX:Math.min(...expandedChain.map(p=>p[0]))-10,
    maxX:Math.max(...expandedChain.map(p=>p[0]))+10,
    minZ:Math.min(...expandedChain.map(p=>p[1]))-10,
    maxZ:Math.max(...expandedChain.map(p=>p[1]))+10
  };
  expandedChain.slice(1).forEach(([x,z],i)=>{
    const [ax,az]=expandedChain[i],length=Math.hypot(x-ax,z-az),g=new T.Group();
    g.name=`boundary-seawall-${i}`;g.position.set((x+ax)/2,0,(z+az)/2);g.rotation.y=-Math.atan2(z-az,x-ax);root.add(g);walls.push(g);
    const h=[4.2,6.3,3.1,8.2,3.8,5.2][i%6];
    box(g,0,(h-12)/2,0,length+1,h+12,3.8,i%3?'#90aca0':'#b4b9a0');
    box(g,0,h+.12,0,length+1.4,.32,4.15,'#d1cbb0');
    for(let k=0;k<3;k++)box(g,(k-1)*length/3,h*.45,2.02,.32,h+1.1,.35,'#6e938d');
    // Broad plaster planes with a few tide bands, not a uniform row of windows.
    box(g,0,1.5,2.03,length,.24,.10,'#b7c7ad');
  });
  const outerCity=createOuterCity({T,root,sources,make,lagoonExpansion:1.30});
  return {root,buildings,walls,outerCity,expansion,boundaryPoint:expand};
}
