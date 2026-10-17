// Painterly water: depth-aware transmission, sparse broad highlights, and world-space wakes.
// All foam/ripple pools are fixed-size; neither clicks nor rowing allocate scene objects.
export function createStylizedWater({ THREE:T, scene, camera, renderer, waterLevel }) {
  const rippleCount=16,wakeCount=24;
  // 岸线水纹的形状来自真实建筑/地块（见 setShore），所以水纹永远跟着建筑走。
  // 数量固定，运行时只改 uniform，不重编译 shader、不分配对象。
  const SHORE_MAX=32;
  const shoreA=Array.from({length:SHORE_MAX},()=>new T.Vector4(0,0,0.01,0.01));
  const shoreB=Array.from({length:SHORE_MAX},()=>new T.Vector4(0,0,0,0));
  const ripples=Array.from({length:rippleCount},()=>new T.Vector4(0,0,-100,0));
  const wakes=Array.from({length:wakeCount},()=>new T.Vector4(0,0,-100,0));
  const target=new T.WebGLRenderTarget(1,1,{minFilter:T.LinearFilter,magFilter:T.LinearFilter,depthBuffer:true,type:T.HalfFloatType});
  target.depthTexture=new T.DepthTexture(1,1,T.UnsignedIntType);
  const uniforms={uTime:{value:0},uRefractionPixels:{value:64},uSurfaceContrast:{value:.25},uSceneColor:{value:target.texture},uSceneDepth:{value:target.depthTexture},
    uResolution:{value:new T.Vector2(1,1)},uNearFar:{value:new T.Vector2(camera.near,camera.far)},uInverseProjection:{value:new T.Matrix4()},uCameraWorld:{value:new T.Matrix4()},
    // Without the old vision mask the far water reads all the way to the plane's edge, so the
    // surface has to sink into the same haze as the rest of the scene instead of ending in a seam.
    // Stored in screen (sRGB) space: the blend happens after tone mapping so it lands on exactly
    // the same final color as the background behind it.
    uFogColor:{value:(scene.fog?scene.fog.color:scene.background).clone().convertLinearToSRGB()},uFogRange:{value:new T.Vector2(scene.fog?scene.fog.near:85,scene.fog?scene.fog.far:175)},
    uBoat:{value:new T.Vector4(0,0,0,0)},uRipples:{value:ripples},uWake:{value:wakes},
    uShoreA:{value:shoreA},uShoreB:{value:shoreB},uShoreCount:{value:0}};
  const material=new T.ShaderMaterial({uniforms,depthWrite:true,side:T.DoubleSide,
    vertexShader:`
      varying vec3 vWaterWorld;
      varying vec4 vWaterClip;
      varying float vWaterViewDepth;
      void main(){
        vec4 world=modelMatrix*vec4(position,1.0);
        vWaterWorld=world.xyz;
        vec4 view=viewMatrix*world;
        vWaterViewDepth=-view.z;
        vWaterClip=projectionMatrix*view;
        gl_Position=vWaterClip;
      }`,
    fragmentShader:`
      uniform float uTime,uRefractionPixels,uSurfaceContrast;
      uniform sampler2D uSceneColor,uSceneDepth;
      uniform vec2 uResolution,uNearFar;
      uniform vec3 uFogColor;
      uniform vec2 uFogRange;
      uniform mat4 uInverseProjection,uCameraWorld;
      uniform vec4 uBoat;
      uniform vec4 uRipples[16],uWake[24];
      // 岸线轮廓：A = (中心x, 中心z, 半宽, 半深)，B = (朝向角, 是否圆形, -, -)。
      // 由 zones.js 的地块与 water-district 的建筑实测填入，搬动建筑只需重新 setShore。
      uniform vec4 uShoreA[32],uShoreB[32];
      uniform float uShoreCount;
      varying vec3 vWaterWorld;
      varying vec4 vWaterClip;
      varying float vWaterViewDepth;
      float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
      float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
        return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
      float broad(vec2 p){return noise(p)*.65+noise(p*2.03+13.2)*.25+noise(p*4.01)*.1;}
      float viewDepth(float z){return uNearFar.x*uNearFar.y/(uNearFar.y-z*(uNearFar.y-uNearFar.x));}
      float boxSDF(vec2 p,vec2 b){vec2 q=abs(p)-b;return length(max(q,0.0))+min(max(q.x,q.y),0.0);}
      vec2 turn(vec2 p,float a){float c=cos(a),s=sin(a);return vec2(c*p.x-s*p.y,s*p.x+c*p.y);}
      float shore(vec2 p){
        float d=1e5;
        for(int i=0;i<32;i++){
          if(float(i)>=uShoreCount)break;
          vec4 a=uShoreA[i],b=uShoreB[i];
          vec2 q=turn(p-a.xy,-b.x);
          // 方形靠 boxSDF，圆形（圆柱楼、圆塔）用同心圆，避免四角鼓出方包。
          d=min(d,mix(boxSDF(q,a.zw),length(q)-max(a.z,a.w),b.y));
        }
        return d;
      }
      void main(){
        vec2 p=vWaterWorld.xz;
        vec2 drift=vec2(uTime*.032,-uTime*.024);
        float swell=broad(p*.12+drift);
        float wash=broad(p*.25+vec2(-uTime*.027,uTime*.019));
        vec2 uv=vWaterClip.xy/vWaterClip.w*.5+.5;
        float rawDepth=texture2D(uSceneDepth,uv).x;
        float thickness=clamp(viewDepth(rawDepth)-vWaterViewDepth,0.0,45.0);
        // Analytic wave derivatives form a continuously changing optical normal.
        float a=dot(p,vec2(.63,.38))+uTime*.72;
        float b=dot(p,vec2(-.29,.91))-uTime*.56;
        float c=dot(p,vec2(1.41,-.73))+uTime*.93;
        vec2 slope=vec2(.63,.38)*cos(a)*.065+vec2(-.29,.91)*cos(b)*.045+vec2(1.41,-.73)*cos(c)*.015;
        vec3 normal=normalize(vec3(-slope.x,1.0,-slope.y));
        // Visible, slow optical motion below the surface; taper at the waterline.
        float refractionDepth=smoothstep(.15,2.5,thickness)*(1.0-smoothstep(24.0,45.0,thickness));
        vec2 refractionOffset=slope*uRefractionPixels/uResolution*refractionDepth;
        vec2 refractUV=clamp(uv+refractionOffset,vec2(.001),vec2(.999));
        if(viewDepth(texture2D(uSceneDepth,refractUV).x)<vWaterViewDepth+.08)refractUV=uv;
        float sampleDepth=texture2D(uSceneDepth,refractUV).x;
        vec3 submerged=texture2D(uSceneColor,refractUV).rgb;
        vec4 beneath=uInverseProjection*vec4(refractUV*2.0-1.0,sampleDepth*2.0-1.0,1.0);
        beneath/=beneath.w;
        vec3 bed=(uCameraWorld*beneath).xyz;
        float depth=max(0.0,vWaterWorld.y-bed.y);
        float deep=smoothstep(2.0,13.0,depth);
        vec3 body=mix(vec3(.008,.30,.25),vec3(.008,.125,.24),deep);
        body*=1.0+(smoothstep(.30,.70,swell)-.5)*.17*uSurfaceContrast;
        // Slow facets of light follow the moving wave field, rather than a texture overlay.
        float waveLight=smoothstep(.10,.85,sin(a)*.45+sin(b)*.35+sin(c)*.20);
        body+=vec3(.002,.018,.020)*waveLight*uSurfaceContrast;
        vec2 waveDomain=p*.27+vec2(sin(p.y*.17+uTime*.18),cos(p.x*.13-uTime*.14))*.55;
        float waterFacet=smoothstep(.44,.56,broad(waveDomain+drift));
        body+=vec3(.002,.036,.034)*waterFacet*uSurfaceContrast;
        // Wavelength-dependent absorption preserves nearby structure and loses reds first.
        vec3 transmission=exp(-thickness*vec3(.125,.064,.046));
        transmission*=1.0-smoothstep(4.0,13.0,depth);
        if(rawDepth>.9999)transmission=vec3(0.0);
        // Moving caustics lie on the submerged geometry, not painted on the surface.
        vec2 cp=bed.xz*.80+vec2(sin(bed.z*.32+uTime*.6),cos(bed.x*.28-uTime*.5))*.42;
        float cells=abs(sin(cp.x+uTime*.30)*cos(cp.y-uTime*.24));
        float caustic=(1.0-smoothstep(.025,.085,cells))*smoothstep(.3,1.2,depth)*(1.0-smoothstep(3.0,15.0,depth));
        submerged+=vec3(.025,.12,.10)*caustic;
        vec3 color=submerged*transmission+body*(1.0-transmission);
        vec3 eye=normalize(cameraPosition-vWaterWorld);
        float fresnel=.02+.98*pow(1.0-max(dot(normal,eye),0.0),5.0);
        color=mix(color,vec3(.16,.39,.51),fresnel*.65);
        vec3 halfLight=normalize(eye+normalize(vec3(.42,.78,-.46)));
        float sun=pow(max(dot(normal,halfLight),0.0),650.0);
        color+=vec3(.26,.45,.42)*sun*.018*smoothstep(.52,.72,wash);
        // Sparse moving flecks, far below the coverage of the former white cloud patches.
        float fleck=smoothstep(.83,.94,noise(p*1.25+drift*2.0))*smoothstep(.55,.74,swell);
        color+=vec3(.025,.055,.052)*fleck*uSurfaceContrast;
        // Soft, broken waterline washes: never a bright wire outlining every wall.
        float edge=shore(p);
        // Wavefronts propagate away from the footprint with a curved, scalloped edge.
        float scallop=sin(p.x*1.5+p.y*1.1-uTime*.75)*.11+sin(p.y*2.4-p.x*.8+uTime*.45)*.045;
        float contact=.10+sin(uTime*1.1+p.x*.28+p.y*.23)*.055;
        float breakup=smoothstep(.31,.58,noise(p*.7+drift*2.0));
        float edgeFoam=(1.0-smoothstep(.035,.115,abs(edge-contact+scallop)))*breakup*step(-.03,edge)*.88;
        float outgoing=0.0;
        for(int band=0;band<2;band++){
          float age=fract(uTime*.23+float(band)*.5+sin(p.x*.25+p.y*.32)*.10);
          float front=.25+age*1.6;
          float crest=1.0-smoothstep(.035,.095,abs(edge-front+scallop*(1.0+age)));
          float envelope=smoothstep(0.0,.12,age)*(1.0-smoothstep(.42,1.0,age));
          outgoing=max(outgoing,crest*envelope*breakup*.42);
        }
        float foam=max(edgeFoam,outgoing*step(0.0,edge));
        // Hull contact plus curved, speed-dependent bow waves.
        vec2 forward=vec2(sin(uBoat.z),cos(uBoat.z)),side=vec2(forward.y,-forward.x);
        vec2 rel=p-uBoat.xy;float along=dot(rel,forward),across=dot(rel,side);
        float hull=length(vec2(across/1.32,along/2.65));
        float hullLap=(1.0-smoothstep(.035,.15,abs(hull-1.03)))*(.18+.16*sin(uTime*1.4+along*2.0));
        foam=max(foam,hullLap);
        float speed=clamp(uBoat.w/3.6,0.0,1.0),tail=-along;
        float width=1.15+tail*.23;
        float bow=(1.0-smoothstep(.05,.23,abs(abs(across)-width))) * smoothstep(-.4,.4,tail)*(1.0-smoothstep(3.0,7.5,tail));
        foam=max(foam,bow*speed*.42*smoothstep(.24,.6,noise(p*1.5-vec2(uTime*.15))));
        // Historical foam positions remain in the water when the boat turns or stops.
        for(int i=0;i<24;i++){
          float age=uTime-uWake[i].z;
          if(age>=0.0&&age<5.0&&uWake[i].w>0.0){
            vec2 d=p-uWake[i].xy;float radius=.22+age*.16;
            float dab=1.0-smoothstep(radius*.30,radius,length(d));
            float breakup=smoothstep(.22,.66,noise(d*5.0+float(i)));
            foam=max(foam,dab*breakup*pow(1.0-age/5.0,1.5)*.55);
          }
        }
        // Clicks, paddle dips and dock contact share gently expanding, broken arcs.
        for(int i=0;i<16;i++){
          float age=uTime-uRipples[i].z;
          if(age>=0.0&&age<3.5&&uRipples[i].w>0.0){
            vec2 d=p-uRipples[i].xy;float radius=.10+age*.88;
            float ring=1.0-smoothstep(.035,.105,abs(length(d)-radius));
            float arc=.45+.55*smoothstep(-.5,.5,sin(atan(d.y,d.x)*3.0+float(i)*2.0));
            float fade=pow(1.0-age/3.5,2.0)*smoothstep(0.0,.12,age);
            foam=max(foam,ring*arc*fade*uRipples[i].w*.66);
            color+=vec3(.008,.023,.021)*(1.0-smoothstep(0.0,.25,abs(length(d)-radius-.14)))*fade;
          }
        }
        color=mix(color,vec3(.96,.985,1.0),clamp(foam,0.0,.96));
        gl_FragColor=vec4(color,1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
        // Fog is blended after tone mapping so the far water lands on the exact screen color of
        // the background it dissolves into; a linear-space blend would leave a visible horizon.
        float fogAmount=clamp((vWaterViewDepth-uFogRange.x)/(uFogRange.y-uFogRange.x),0.0,1.0);
        gl_FragColor.rgb=mix(gl_FragColor.rgb,uFogColor,fogAmount);
      }`
  });
  // Sized well past the camera's far plane so its own edge never becomes a horizon seam now that
  // nothing masks the distance; the fog blend above carries the surface out of sight first.
  const surface=new T.Mesh(new T.PlaneGeometry(640,640),material);
  surface.name='cartoon-water';surface.rotation.x=-Math.PI/2;surface.position.y=waterLevel;surface.renderOrder=3;scene.add(surface);
  const stats={clicks:0,oarStrokes:0,landings:0,wakeSamples:0};
  let art=null,rippleIndex=0,wakeIndex=0,lastT=0,oldMode='',stroke=-1,speed=0,travel=0,initialized=false;
  const previous=new T.Vector3(),pos=new T.Vector3(),pointer=new T.Vector2(),ray=new T.Raycaster(),hit=new T.Vector3();
  const plane=new T.Plane(new T.Vector3(0,1,0),-waterLevel);
  const emitRipple=(x,z,strength=1)=>{ripples[rippleIndex].set(x,z,lastT,strength);rippleIndex=(rippleIndex+1)%rippleCount;};
  function bind(value){art=value;}
  // 岸线水纹的轮廓从这里进来：每项 { x, z, hx, hz, angle?, round? }（世界坐标，半宽/半深）。
  // 区块地块与场景建筑实测后各交一份，搬动任何东西只需要再调一次。
  function setShore(shapes){
    const list=shapes||[],n=Math.min(list.length,SHORE_MAX);
    for(let i=0;i<n;i++){
      const s=list[i];
      shoreA[i].set(s.x,s.z,Math.max(s.hx,.01),Math.max(s.hz,.01));
      shoreB[i].set(s.angle||0,s.round?1:0,0,0);
    }
    uniforms.uShoreCount.value=n;
  }
  function update(dt,t){
    lastT=t;uniforms.uTime.value=t;if(!art)return;
    art.boatAnchorGroup.getWorldPosition(pos);
    const delta=initialized?Math.hypot(pos.x-previous.x,pos.z-previous.z):0;
    const moving=art.state.workerMode==='ROWING';
    const targetSpeed=moving&&dt>0?Math.min(6,delta/dt):0;
    speed=T.MathUtils.lerp(speed,targetSpeed,1-Math.exp(-Math.min(dt,.1)*7));
    const yaw=art.boatAnchorGroup.rotation.y;
    uniforms.uBoat.value.set(pos.x,pos.z,yaw,speed);
    if(moving&&delta<3){travel+=delta;if(travel>.42){travel=0;const side=(wakeIndex%2?1:-1)*.26;
      wakes[wakeIndex].set(pos.x-Math.sin(yaw)*2.75+Math.cos(yaw)*side,pos.z-Math.cos(yaw)*2.75-Math.sin(yaw)*side,t,1);
      wakeIndex=(wakeIndex+1)%wakeCount;stats.wakeSamples++;}}
    const nextStroke=Math.floor(t*4.5/(Math.PI*2));
    if(moving&&nextStroke!==stroke){stroke=nextStroke;stats.oarStrokes++;
      for(const side of [-1,1])emitRipple(pos.x+Math.cos(yaw)*2.6*side,pos.z-Math.sin(yaw)*2.6*side,.55);
    }
    if(oldMode==='ROWING'&&!moving){stats.landings++;emitRipple(pos.x,pos.z,.8);}
    oldMode=art.state.workerMode;previous.copy(pos);initialized=true;
  }
  function renderUnderwater(){
    const bounds=renderer.getSize(new T.Vector2()),ratio=Math.min(renderer.getPixelRatio(),1.25);
    const w=Math.round(bounds.x*ratio),h=Math.round(bounds.y*ratio);
    if(target.width!==w||target.height!==h){target.setSize(w,h);uniforms.uResolution.value.set(w,h);}
    uniforms.uNearFar.value.set(camera.near,camera.far);
    uniforms.uInverseProjection.value.copy(camera.projectionMatrixInverse);
    uniforms.uCameraWorld.value.copy(camera.matrixWorld);
    const saved=renderer.getRenderTarget(),visible=surface.visible;
    surface.visible=false;
    try {renderer.setRenderTarget(target);renderer.render(scene,camera);}
    finally {renderer.setRenderTarget(saved);surface.visible=visible;}
  }
  let down=null;
  const canvas=renderer.domElement;
  canvas.addEventListener('pointerdown',e=>{down={x:e.clientX,y:e.clientY,id:e.pointerId};});
  canvas.addEventListener('pointercancel',()=>{down=null;});
  canvas.addEventListener('pointerup',e=>{
    const start=down;down=null;
    if(!art||e.button!==0||!start||start.id!==e.pointerId||Math.hypot(e.clientX-start.x,e.clientY-start.y)>5)return;
    const r=canvas.getBoundingClientRect();pointer.set((e.clientX-r.left)/r.width*2-1,1-(e.clientY-r.top)/r.height*2);
    ray.setFromCamera(pointer,camera);if(!ray.ray.intersectPlane(plane,hit))return;
    const distance=ray.ray.origin.distanceTo(hit);
    const obstacle=ray.intersectObjects(scene.children,true).find(h=>{
      if(h.object===surface||h.distance>=distance-.08||h.point.y<waterLevel+.08)return false;
      for(let o=h.object;o;o=o.parent)if(!o.visible)return false;
      return true;
    });
    if(obstacle)return;stats.clicks++;emitRipple(hit.x,hit.z,.85);
  });
  return {surface,uniforms,stats,emitRipple,bind,setShore,update,renderUnderwater};
}
