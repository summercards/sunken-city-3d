// Real-time scene transmission through a displaced water interface, viewed from below.
// No bitmap water texture: waves, normals, Fresnel highlights and UV deflection are procedural.
export function createUnderwaterOptics({THREE:T,scene,root,waterLevel,time}) {
  const target=new T.WebGLRenderTarget(1,1,{type:T.HalfFloatType,depthBuffer:true});
  target.depthTexture=new T.DepthTexture(1,1,T.UnsignedIntType);
  const uniforms={time,sceneColor:{value:target.texture},sceneDepth:{value:target.depthTexture},resolution:{value:new T.Vector2(1,1)}};
  const ceiling=new T.Mesh(new T.PlaneGeometry(180,180,100,100),new T.ShaderMaterial({
    side:T.DoubleSide,uniforms,
    vertexShader:`uniform float time;varying vec3 world;varying vec4 clip;
      float wave(vec2 p){return sin(p.x*.72+time*.85)*.10+sin(p.y*.93-time*.69)*.07+sin((p.x+p.y)*1.8+time*1.1)*.025;}
      void main(){vec4 w=modelMatrix*vec4(position,1.);w.y+=wave(w.xz);world=w.xyz;clip=projectionMatrix*viewMatrix*w;gl_Position=clip;}`,
    fragmentShader:`uniform float time;uniform sampler2D sceneColor,sceneDepth;uniform vec2 resolution;
      varying vec3 world;varying vec4 clip;
      void main(){
        vec2 p=world.xz;
        vec2 slope=vec2(.072*cos(p.x*.72+time*.85)+.045*cos((p.x+p.y)*1.8+time*1.1),.065*cos(p.y*.93-time*.69)+.045*cos((p.x+p.y)*1.8+time*1.1));
        vec3 n=normalize(vec3(-slope.x,-1.,-slope.y));
        vec3 v=normalize(cameraPosition-world);
        float fresnel=.035+.965*pow(1.-abs(dot(n,v)),5.);
        vec2 uv=clip.xy/clip.w*.5+.5;
        vec2 bend=slope*vec2(48.,38.)/resolution;
        vec2 sampleUV=clamp(uv+bend,vec2(.002),vec2(.998));
        // Keep foreground underwater geometry from leaking into the transmitted surface.
        float surfaceZ=clip.z/clip.w*.5+.5;
        if(texture2D(sceneDepth,sampleUV).x<surfaceZ-.001)sampleUV=uv;
        vec3 through=texture2D(sceneColor,sampleUV).rgb;
        vec3 sky=vec3(.12,.62,.68);
        float glint=pow(max(0.,dot(reflect(-normalize(vec3(.25,-1.,.15)),n),v)),90.);
        vec3 c=mix(through*vec3(.9,1.,.97),sky,fresnel*.6)+vec3(1.,.96,.77)*glint*.65;
        gl_FragColor=vec4(c,1.);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`
  }));
  ceiling.rotation.x=-Math.PI/2;ceiling.position.y=waterLevel;ceiling.name='refracting-underwater-surface';root.add(ceiling);
  const size=new T.Vector2(),direction=new T.Vector3();let renders=0;
  function render(renderer,camera){
    camera.getWorldDirection(direction);
    // In the default downward view the interface is behind the camera; no redundant offscreen pass.
    if(camera.position.y<waterLevel-.3&&direction.y<-.3)return;
    renderer.getSize(size);const ratio=Math.min(renderer.getPixelRatio(),1.25);
    const w=Math.round(size.x*ratio),h=Math.round(size.y*ratio);
    if(target.width!==w||target.height!==h){target.setSize(w,h);uniforms.resolution.value.set(w,h);}
    const oldTarget=renderer.getRenderTarget(),oldShadow=renderer.shadowMap.autoUpdate;
    ceiling.visible=false;renderer.shadowMap.autoUpdate=false;
    try{renderer.setRenderTarget(target);renderer.render(scene,camera);renders++;}
    finally{renderer.setRenderTarget(oldTarget);renderer.shadowMap.autoUpdate=oldShadow;ceiling.visible=true;}
  }
  return {ceiling,uniforms,render,get renders(){return renders;}};
}
