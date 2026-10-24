// Navigation and motion use the same convex footprint and swept collision queries.
// Pure data module: headings are THREE rotation.y; the rendered bow faces local -Z.
import { createNavGrid, planRoute, isFree } from './sail-nav.js';

export const angleDelta = (a, b) => Math.atan2(Math.sin(b - a), Math.cos(b - a));
export function convexHull(points) {
  const sorted = [...new Map(points.map(p => [`${p.x.toFixed(5)},${p.z.toFixed(5)}`, p])).values()]
    .sort((a, b) => a.x - b.x || a.z - b.z);
  const cross = (a, b, c) => (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x);
  const half = list => { const out=[]; for (const p of list) { while(out.length>1 && cross(out.at(-2),out.at(-1),p)<=0) out.pop(); out.push(p); } return out; };
  return [...half(sorted).slice(0,-1), ...half(sorted.slice().reverse()).slice(0,-1)];
}

export function createBoatNavigator({ rects, bounds, hull, cell = .5 }) {
  const radius = Math.max(...hull.map(p => Math.hypot(p.x,p.z))) + .06;
  const halfWidth = Math.max(...hull.map(p => Math.abs(p.x))) + .06;
  const buckets = new Map(), bucketSize=8;
  for(const r of rects) for(let x=Math.floor(r.minX/bucketSize);x<=Math.floor(r.maxX/bucketSize);x++)
    for(let z=Math.floor(r.minZ/bucketSize);z<=Math.floor(r.maxZ/bucketSize);z++) {
      const key=`${x},${z}`; if(!buckets.has(key))buckets.set(key,[]); buckets.get(key).push(r);
    }
  const nearby = (x,z) => {
    const found=new Set();
    for(let i=Math.floor((x-radius)/bucketSize);i<=Math.floor((x+radius)/bucketSize);i++)
      for(let j=Math.floor((z-radius)/bucketSize);j<=Math.floor((z+radius)/bucketSize);j++)
        for(const r of buckets.get(`${i},${j}`)||[]) found.add(r);
    return found;
  };
  function clear(p) {
    if(![p.x,p.z,p.yaw].every(Number.isFinite))return false;
    const c=Math.cos(p.yaw),s=Math.sin(p.yaw);
    const poly=hull.map(v=>({x:p.x+v.x*c+v.z*s,z:p.z-v.x*s+v.z*c}));
    const minX=Math.min(...poly.map(v=>v.x)),maxX=Math.max(...poly.map(v=>v.x));
    const minZ=Math.min(...poly.map(v=>v.z)),maxZ=Math.max(...poly.map(v=>v.z));
    if(minX<bounds.minX||maxX>bounds.maxX||minZ<bounds.minZ||maxZ>bounds.maxZ)return false;
    for(const r of nearby(p.x,p.z)) {
      if(maxX<r.minX-.04||minX>r.maxX+.04||maxZ<r.minZ-.04||minZ>r.maxZ+.04)continue;
      const corners=[{x:r.minX-.04,z:r.minZ-.04},{x:r.maxX+.04,z:r.minZ-.04},{x:r.maxX+.04,z:r.maxZ+.04},{x:r.minX-.04,z:r.maxZ+.04}];
      let separated=false;
      for(let i=0;i<poly.length;i++) {
        const a=poly[i],b=poly[(i+1)%poly.length],nx=-(b.z-a.z),nz=b.x-a.x;
        const hp=poly.map(v=>v.x*nx+v.z*nz),rp=corners.map(v=>v.x*nx+v.z*nz);
        if(Math.max(...hp)<Math.min(...rp)||Math.max(...rp)<Math.min(...hp)){separated=true;break;}
      }
      if(!separated)return false;
    }
    return true;
  }
  function sweep(a,b) {
    const turn=angleDelta(a.yaw,b.yaw),distance=Math.hypot(b.x-a.x,b.z-a.z);
    // Bound the displacement of every hull vertex, including rotation at rest.
    const count=Math.max(1,Math.ceil((distance+Math.abs(turn)*radius)/.10));
    for(let i=0;i<=count;i++) {
      const t=i/count;
      if(!clear({x:a.x+(b.x-a.x)*t,z:a.z+(b.z-a.z)*t,yaw:a.yaw+turn*t}))return false;
    }
    return true;
  }
  let grids;
  function getGrids() {
    return grids ||= [radius+.18, halfWidth+.18].map(clearance=>createNavGrid({rects,bounds,cell,clearance}));
  }
  function append(poses,p) {
    const last=poses.at(-1);
    if(!last || Math.hypot(last.x-p.x,last.z-p.z)>.001 || Math.abs(angleDelta(last.yaw,p.yaw))>.001)poses.push({...p});
  }
  function addTravel(poses,point) {
    const last=poses.at(-1),distance=Math.hypot(point.x-last.x,point.z-last.z);
    if(distance<.001)return true;
    const yaw=Math.atan2(point.x-last.x,point.z-last.z)+Math.PI;
    const turned={...last,yaw},next={...point,yaw};
    if(!sweep(last,turned)||!sweep(turned,next))return false;
    append(poses,turned);append(poses,next);return true;
  }
  // Exit/approach along the hull axis; backing out does not require a 180° turn
  // beside the quay. Only use an angled exit when its initial turn is clear.
  function connectors(p,grid,arrival=false) {
    const candidates=[];
    for(const offset of [0,Math.PI/4,-Math.PI/4,Math.PI/2,-Math.PI/2]) {
      const aligned={...p,yaw:p.yaw+offset};
      if(!sweep(p,aligned))continue;
      for(const distance of [0,2,4,6,9,12]) for(const sign of distance?[1,-1]:[1]) {
        const end={x:p.x+Math.sin(aligned.yaw)*distance*sign,z:p.z+Math.cos(aligned.yaw)*distance*sign,yaw:aligned.yaw};
        if(!isFree(grid,end.x,end.z)||!sweep(aligned,end))continue;
        const poses=[];append(poses,p);append(poses,aligned);append(poses,end);
        candidates.push({point:end,poses:arrival?poses.reverse():poses,cost:distance+Math.abs(offset)*2});
        // Shortest clear point along each direction suffices; longer points are
        // reached by the same free grid and need not trigger another A* search.
        break;
      }
    }
    return candidates.sort((a,b)=>a.cost-b.cost).slice(0,10);
  }
  function plan(start,goal) {
    if(!clear(start))return null;
    const freeYaw=!Number.isFinite(goal.yaw);
    const direct=[{...start}];
    if(addTravel(direct,goal)) {
      const last=direct.at(-1),end={...goal,yaw:freeYaw?last.yaw:goal.yaw};
      if(sweep(last,end)){append(direct,end);return makeRoute(direct);}
    }
    const goals=freeYaw ? [start.yaw,Math.atan2(goal.x-start.x,goal.z-start.z)+Math.PI,0,Math.PI/2,Math.PI,-Math.PI/2].map(yaw=>({...goal,yaw})) : [goal];
    for(const grid of getGrids()) {
      const starts=connectors(start,grid);
      const ends=goals.filter(clear).flatMap(g=>connectors(g,grid,true)).sort((a,b)=>a.cost-b.cost).slice(0,12);
      const pairs=starts.flatMap(a=>ends.map(b=>({a,b,cost:a.cost+b.cost+Math.hypot(a.point.x-b.point.x,a.point.z-b.point.z)}))).sort((a,b)=>a.cost-b.cost);
      for(const {a,b} of pairs) {
        const mid=planRoute(grid,a.point,b.point);if(!mid)continue;
        const poses=a.poses.map(p=>({...p}));let ok=true;
        for(const p of mid.slice(1))if(!addTravel(poses,p)){ok=false;break;}
        if(!ok)continue;
        for(const p of b.poses) { if(!sweep(poses.at(-1),p)){ok=false;break;} append(poses,p); }
        if(ok)return makeRoute(poses);
      }
    }
    return null;
  }
  return {clear,sweep,plan,radius,halfWidth};
}

function makeRoute(poses) {
  const length=poses.slice(1).reduce((n,p,i)=>n+Math.hypot(p.x-poses[i].x,p.z-poses[i].z),0);
  return {poses,index:1,distance:0,length,getLength:()=>length};
}

// Commit only swept, accepted movement. No elapsed-time "arrival" or collision
// push: a blocked pose leaves both position and route cursor unchanged.
export function advanceBoat(route,pose,dt,navigator,{speed=2.4,turnSpeed=3.4}={}) {
  if(!route||!Number.isFinite(dt)||dt<=0)return {pose,arrived:false,blocked:false};
  let remaining=Math.min(dt,.1),current={...pose},blocked=false;
  while(route.index<route.poses.length && remaining>1e-7) {
    const target=route.poses[route.index],distance=Math.hypot(target.x-current.x,target.z-current.z),turn=angleDelta(current.yaw,target.yaw);
    const duration=Math.max(distance/speed,Math.abs(turn)/turnSpeed);
    if(duration<1e-7){route.index++;continue;}
    const fraction=Math.min(1,remaining/duration);
    const next={x:current.x+(target.x-current.x)*fraction,z:current.z+(target.z-current.z)*fraction,yaw:current.yaw+turn*fraction};
    if(!navigator.sweep(current,next)){blocked=true;break;}
    route.distance+=distance*fraction;current=next;remaining-=duration*fraction;
    if(fraction>=1)route.index++;
  }
  const end=route.poses.at(-1);
  const arrived=route.index>=route.poses.length && Math.hypot(current.x-end.x,current.z-end.z)<.02 && Math.abs(angleDelta(current.yaw,end.yaw))<.02;
  return {pose:current,arrived,blocked};
}
