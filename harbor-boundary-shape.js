// Local outward offsets from the red-line layout review. Apply the same map to
// the front wall, its towers/footings, and the dense city immediately behind it.
// Northern shoulders blend back into their existing positions.
const smooth=(a,b,v)=>{const t=Math.max(0,Math.min(1,(v-a)/(b-a)));return t*t*(3-2*t);};
export function moveHarborBoundary(x,z) {
  const west=smooth(15,65,-x),east=smooth(20,70,x),south=smooth(0,65,z);
  return [
    x-16*west*smooth(-55,-10,z)+14*east*smooth(-65,-20,z),
    z+14*south+4*west*smooth(10,50,z)
  ];
}
