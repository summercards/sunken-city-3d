// Local effects are composed in the ocean material, so depth, waves, light and
// occlusion stay shared. No floating discs or boat-parented foam geometry.
uniform vec4 boat_hull_points[24]; // world x/z, contact height
uniform int boat_hull_count = 0;
// Blade entries are their own channel. Feeding `u_ripples` instead stacked the
// oar splash on top of the generic ripple ring the same uniforms already draw,
// which read as a bullseye inside a second bullseye.
uniform vec4 boat_blade_points[8]; // world x/z, entry time, strength
uniform int boat_blade_count = 0;
uniform float boat_contact_strength = 1.0;
uniform float boat_oar_strength = 1.0;

float bwc_hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// Value noise, kept local so this include does not depend on where the host
// shader happens to declare its own.
float bwc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bwc_hash(i), bwc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(bwc_hash(i + vec2(0.0, 1.0)), bwc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float boat_hull_distance(vec2 p) {
	float nearest=100.0;
	for (int i=0;i<24;i++) {
		if(i>=boat_hull_count)break;
		int next=(i+1)%boat_hull_count;
		vec2 a=boat_hull_points[i].xy;
		vec2 b=boat_hull_points[next].xy;
		vec2 ab=b-a;
		float f=clamp(dot(p-a,ab)/max(dot(ab,ab),0.0001),0.0,1.0);
		nearest=min(nearest,length(p-a-ab*f));
	}
	return nearest;
}

// x = hull meniscus/wash, y = splash thrown by each real blade entry.
vec2 boat_water_foam(vec2 p) {
	float hull=0.0;
	if(boat_hull_count>2 && distance(p,u_boat.xy)<5.5) {
		float d=boat_hull_distance(p);
		float aa=max(fwidth(d),0.018);
		// A constant-width band traced the hull exactly and read as a sticker
		// outline. Real displacement is ragged: the gap breathes along the
		// waterline, thins at the ends and breaks in the middle.
		float grain=bwc_noise(p*3.6+vec2(u_time*0.13,-u_time*0.09));
		float fine=bwc_noise(p*11.0-vec2(u_time*0.21,0.0));
		float swell=0.020*sin(dot(p,vec2(3.1,2.3))+u_time*1.6);
		float gap=0.045+0.070*fine+0.035*grain+swell;
		float rim=1.0-smoothstep(gap,gap+0.038+aa,d);
		rim*=smoothstep(0.16,0.58,grain+0.26);
		// One slow ring of water shoved outward, also broken rather than drawn.
		float phase=fract(u_time*0.46);
		float expanding=0.22+phase*0.72;
		float wash=1.0-smoothstep(0.030,0.068+aa,abs(d-expanding+swell));
		float gaps=smoothstep(-0.15,0.55,sin(dot(p,vec2(4.7,-3.1))-u_time*.75)+0.35*(fine-0.5));
		wash*=sin(phase*3.14159265)*gaps*.42;
		hull=max(rim*.62,wash)*boat_contact_strength;
	}
	float oars=0.0;
	// Backward direction in the same convention `ocean_waves` uses for the bow.
	vec2 backward=vec2(sin(u_boat.z),cos(u_boat.z));
	vec2 across_oar=vec2(-backward.y,backward.x);
	for(int i=0;i<8;i++) {
		if(i>=boat_blade_count)break;
		vec4 bp=boat_blade_points[i];
		float age=u_time-bp.z;
		if(age<0.0 || age>1.7)continue;
		vec2 rel=p-bp.xy;
		float dist=length(rel);
		if(dist>1.7)continue;
		// Foam in this ocean is broken white flecks, never an outline. Each
		// attempt at an arc or a V read as a shape drawn on the water — the
		// eye reads thin continuous curves as vector art. So the splash is the
		// same substance as the surrounding foam: a patch of flecks laid in the
		// wedge the blade pushed, densest at the blade and thinning aft.
		float along=dot(rel,backward);
		float sideways=dot(rel,across_oar);
		float reach=0.30+age*0.75;
		if(along<-0.10 || along>reach)continue;
		float wedge=0.14+along*0.70;             // half-width grows aft
		float inside=1.0-smoothstep(wedge*0.40,wedge,abs(sideways));
		float fade=1.0-smoothstep(reach*0.45,reach,along);
		if(inside<=0.0 || fade<=0.0)continue;
		// Flecks: thresholded value noise at roughly the scale the sea's own
		// foam uses in this frame, drifting aft as the water settles.
		vec2 drift=backward*(age*0.55)+vec2(float(i)*11.0);
		float fleck=bwc_noise((p-drift)*13.0);
		float fleck2=bwc_noise((p-drift)*27.0);
		float mask=smoothstep(0.58,0.70,fleck)*0.75+smoothstep(0.70,0.82,fleck2)*0.25;
		// Closest to the blade the water is churned solid; it breaks up fast.
		float churn=(1.0-smoothstep(0.04,0.26,dist))*0.85;
		float body=max(mask,churn*(0.45+0.55*bwc_noise(p*18.0)));
		// Overall settle: the patch thins and fades as the stroke completes.
		float settle=(1.0-smoothstep(0.20,1.55,age))*bp.w;
		oars=max(oars,body*inside*fade*settle);
	}
	return clamp(vec2(hull,oars*boat_oar_strength),vec2(0.0),vec2(.95));
}
