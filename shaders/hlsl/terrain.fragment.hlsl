#include "ShaderConstants.fxh"
#include "util.fxh"

struct PS_Input
{
	float4 position : SV_Position;
	float3 pos : pos;
	float waterFlag : waterFlag;
	float3 wP : Wp;

#ifndef BYPASS_PIXEL_SHADER
	lpfloat4 color : COLOR;
	snorm float2 uv0 : TEXCOORD_0_FB_MSAA;
	snorm float2 uv1 : TEXCOORD_1_FB_MSAA;
#endif

#ifdef FOG
	float4 fogColor : FOG_COLOR;
#endif
};

struct PS_Output
{
	float4 color : SV_Target;
};

// ▼ Tone map function
float3 ACESFilm(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}
// ▲ Tone map function

// ▼ Hash, Noise Functions
float hash(float2 p) {
    float3 p3 = frac(float3(p.xyx) * 0.13); 
    p3 += dot(p3, p3.yzx + 3.33); 
    return frac((p3.x + p3.y) * p3.z); 
}
float noise (in float2 st) {
    float2 i = floor(st);
    float2 f = frac(st);
    // Four corners in 2D of a tile
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    // Smooth Interpolation
    // Cubic Hermine Curve.  Same as SmoothStep()
    float2 u = f*f*(3.0-2.0*f);
    // u = smoothstep(0.,1.,f);
    // Mix 4 coorners percentages

    st.x -= TOTAL_REAL_WORLD_TIME * 0.03 * st.x;

    return lerp(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}
#define OCTAVES 5
float fbm(float2 x) {
    float final = 0.0;
    float a = 0.5;
    for (int i = 0; i < OCTAVES; ++i) {
        final += a * noise(x);
        x *= 2.0;
        a *= 0.5;
        x.xy -= TOTAL_REAL_WORLD_TIME * 0.03 * float(i + 1);
    }
    return final;
}
// ▲ Hash, Noise Functions


ROOT_SIGNATURE
void main(in PS_Input PSInput, out PS_Output PSOutput)
{
#ifdef BYPASS_PIXEL_SHADER
    PSOutput.color = float4(0.0f, 0.0f, 0.0f, 0.0f);
    return;
#else
/*#if !defined(ALPHA_TEST) && !defined(BLEND)
	// ▼ pom
	float2 pom = 0.000984251968503937;
	#if USE_TEXEL_AA
    	float4 diffuse = texture2D_AA(TEXTURE_0, TextureSampler0, PSInput.uv0);
		diffuse +=  abs(texture2D_AA(TEXTURE_0, TextureSampler0, PSInput.uv0 + (pom/6)));
	#else
    	float4 diffuse = TEXTURE_0.Sample(TextureSampler0, PSInput.uv0);
		diffuse += abs(TEXTURE_0.Sample(TextureSampler0, PSInput.uv0 + (pom/6)));
	#endif
	// ▲ pom
#else*/
	#if USE_TEXEL_AA
		float4 diffuse = texture2D_AA(TEXTURE_0, TextureSampler0, PSInput.uv0 );
	#else
		float4 diffuse = TEXTURE_0.Sample(TextureSampler0, PSInput.uv0);
	#endif
//#endif

#ifdef SEASONS_FAR
	diffuse.a = 1.0f;
#endif

#if USE_ALPHA_TEST
	#ifdef ALPHA_TO_COVERAGE
		#define ALPHA_THRESHOLD 0.05
	#else
		#define ALPHA_THRESHOLD 0.5
	#endif
	if(diffuse.a < ALPHA_THRESHOLD)
		discard;
#endif

#if defined(BLEND)
	diffuse.a *= PSInput.color.a;
#endif

#if !defined(ALWAYS_LIT)
// ▼ Self lightig(廃止)
//float2 lightCoord = PSInput.uv1;// x=🕯 y=☀
//lightCoord.x = lerp(1.0, lightCoord.x, length(-PSInput.wP) / RENDER_DISTANCE * 128.0);
//diffuse = diffuse * TEXTURE_1.Sample(TextureSampler1, lightCoord);
// ▲ Self lightig(廃止)
// ↓ original
#if !defined(ALWAYS_LIT)
diffuse = diffuse * TEXTURE_1.Sample(TextureSampler1, PSInput.uv1);
#endif

#endif

#ifndef SEASONS
	#if !USE_ALPHA_TEST && !defined(BLEND)
		diffuse.a = PSInput.color.a;
	#endif	

	diffuse.rgb *= PSInput.color.rgb;
#else
	float2 uv = PSInput.color.xy;
	diffuse.rgb *= lerp(1.0f, TEXTURE_2.Sample(TextureSampler2, uv).rgb*2.0f, PSInput.color.b);
	diffuse.rgb *= PSInput.color.aaa;
	diffuse.a = 1.0f;
#endif




diffuse.rgb = pow(diffuse.rgb, 1.28); // pow pow

// ▼ BLEND S
#if defined(BLEND)
float3 tx = diffuse.rgb;
const float S = 2.3;
if(tx.r > tx.g && tx.r > tx.b) {
	diffuse.r *= S;
} else {
	if(tx.g > tx.r && tx.g > tx.b) {
		diffuse.g *= S;
	} else {
		if(tx.b > tx.r && tx.b > tx.g) {
			diffuse.b *= S;
		}
	}	
}
#endif
// ▲ BLEND S

// DB
float isDay = TEXTURE_1.Sample(TextureSampler1, float2(0.0, 1.0)).r;
float isRain = smoothstep(0.5, 0.4, FOG_CONTROL.x);

//Shadow
float shadow = lerp(0.5, 1.0, smoothstep(0.84, 0.90, PSInput.uv1.y));
diffuse.rgb *= lerp(shadow, 1.0, PSInput.uv1.x);

// ▼ Light
const float3 dayLight = float3(1.5, 0.08, 0.0) * 2.0;
const float3 rainLight = float3(1.0, 0.65, 0.0) * 1.4;

float lightIntensity = lerp(pow(PSInput.uv1.x, 2.0), 0.0, isDay * PSInput.uv1.y);
float3 lightColor = lerp(float3(1.0, 0.3, 0.0)*2.2, lerp(dayLight, rainLight, isRain), PSInput.uv1.y);// Branching in the rain and indoor light (because the colors were too bright)
float3 lightColorInUW = lerp(float3(0.0, 0.95, 1.0) * 1.5, float3(0.0, 1.0, 0.7) * 1.5, PSInput.uv1.y);// Under Water
if (FOG_CONTROL.x != 0.0) {
	diffuse.rgb *= lerp(1.0, lightColor , lightIntensity) * max(PSInput.uv1.x-1.575, 1.0);
} else {// Under water lighting
	diffuse.rgb *= lerp(1.0, lightColorInUW , lightIntensity) * max(PSInput.uv1.x-1.8, 1.0);//
}
// ▲ Light

//Tone map
diffuse.rgb = ACESFilm(diffuse.rgb * 2.0);

// ▼ Reflection from alpha
float3 posN = normalize(PSInput.wP);
#if !defined(BLEND)
if (TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).a < 0.9) {
	diffuse.rgb += float3(1.0, 1.0, .9) * max(PSInput.uv1.x-.4, 0.) * smoothstep(0.9, 0.45, TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).a);
	if(PSInput.color.a != 0.0) {// happ ahajog ayy
		// ↓ clouds Ref
		diffuse.rgb += lerp(float3(0.29, 0.38 ,0.74)*0.3, float3(1.0, 1.0, 0.95), smoothstep(0.4, 0.77, fbm((posN.xz+posN.xy/2) * 5.7)))*0.3;
	}
}
#endif
// ▲ Reflection from alpha

// ▼ Water surface reflectionworldPos
float3 posR = PSInput.pos;
float TRWT = TOTAL_REAL_WORLD_TIME;
float3 N = saturate(normalize(cross(ddx(-PSInput.pos), ddy(PSInput.pos))));// Nomal map
float isTop = max(N.y, -N.y);

float wtrReflectTop = clamp(noise(TRWT * 1.7 + posR.xz) - noise(TRWT * 0.39 + posR.xz + float2(TRWT * 1.2 + posR.x + posR.z, TRWT * 1.6 + posR.x + posR.z)), 0.0, 100.0);
float wtrReflectSide = noise(TRWT * 0.39 + posR.xz + float2(TRWT * 1.2 + posR.x + posR.z, TRWT * 1.6 + posR.x + posR.z) - (posR.y*0.2));
float wtrReflect = lerp(wtrReflectSide, wtrReflectTop, isTop);// sideRef / topRef

float notReflect = smoothstep(0.78, 0.90, PSInput.uv1.y);// Does not reflect because sunlight and moonlight do not reach
float noiseLevel = lerp(0.0, smoothstep(0.1, 1.0, wtrReflect), notReflect);// Noise considering shade
if(PSInput.waterFlag > 0.5) {
	// ↓ Base water color  and  alpha
	diffuse.a -= 0.08;
	diffuse.rgb += float3(0.46667, 1.0, 0.90196)*0.25;

	// ↓ from Light
	diffuse.a += (1.1) * max(PSInput.uv1.x-.5, 0.) * smoothstep(0.60391, 0.93726, TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).r);

	// ↓ Main reflection
	float4 nightRef = lerp(0.0, float4(0.8, 0.8, 0.8, 1.0), noiseLevel)*0.2;
	float4 dayRef = lerp(0.0, float4(1.0, 1.0, 1.0, lerp(3.0, 1.0, isTop)), noiseLevel)*0.13;

    float4 lastWtrRef = saturate(lerp(nightRef, dayRef, smoothstep(0.4, 0.7, isDay)));

	diffuse.rgba += lerp(lastWtrRef*0.45, lastWtrRef, isTop);// sideRef / topRef	
	diffuse.rgb -= lerp(float3(0.2,0.2,0.29), 0.0, isTop);// Darken the side
	diffuse.g *= 1.2;// Toooo Green
}
// ▲ Water surface reflection

// ▼ glass wind
float glassReflect = fbm(TRWT * 0.39 + posR.xz + float2(TRWT * 1.2 + posR.x + posR.z, TRWT * 1.6 + posR.z + posR.x) - (posR.y*2));
float fbmLevel = lerp(0.0, smoothstep(0.1, 1.0, glassReflect), notReflect);// Noise considering shade

float windIntensity = lerp(0.09, 0.2, isDay);
float wind = dot(float4(posR, TRWT), float4(0.2, 0.5, 0.3, 3.0));
#if !defined(BLEND) && !defined(ALPHA_TEST)
if (TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).a > 0.99607 && TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).a != 1.0) {
	float glassWindResult = lerp(fbmLevel, 0.0, isRain);// Eliminate the wind in case of rain
    diffuse.rgb += saturate(glassWindResult) * windIntensity * saturate(wind);
}
#endif
// ▲ glass wind

// ▼ puddle
float3 pos_forPuddle = abs(PSInput.pos.xyz - 8.0);
float puddle = smoothstep(-5.5, 0.77, noise(pos_forPuddle.xz * 2.5));
float puddleLevel = lerp(0.0, smoothstep(0.1, 1.0, puddle), notReflect);// mizutamaryy
float3 puddleColor = float3(0.74902, 1.0, 1.0)*3;
float puddleII = smoothstep(-2.8, RENDER_DISTANCE*0.074+2.3, length(PSInput.wP));

if (N.y > 0.9 && N.y > -N.y && FOG_CONTROL.x != 0) {//top face    ((Does not detect underwater
	float3 pudlleResult = lerp(0.0, lerp(0.0, puddleColor, puddleLevel), isRain);
    diffuse.rgb += saturate(pudlleResult) * windIntensity * saturate(wind) * 1.2;
	diffuse.rgb -= lerp(0.0, 0.23, isRain);
	diffuse.b *= lerp(1.0, 1.5, isRain);
	diffuse.rgb = lerp(diffuse.rgb, lerp(diffuse.rgb, lerp(diffuse.rgb, float3(0.8, 0.8, 0.8), puddleII), isRain), PSInput.uv1.y);//puddleII
}
// ▲ puddle


// ▼ UnderWater Ref
if (FOG_CONTROL.x == 0.0) {
	float UWReflect = noise(TRWT * 0.42 + posR.xz + float2(TRWT * 1.2 + posR.x + posR.z, TRWT * 1.6 + posR.x + posR.z));
	float noiseLevelUW = smoothstep(0.1, 1.0, UWReflect);
	float3 UWRef = saturate(lerp(0.0, float3(0.34, 1.4, 1.0), noiseLevelUW))*0.2;
	diffuse.rgb += UWRef;// sideRef / topRef
	diffuse.rgb += float3(0, 1.3, 1.7)*0.3;
}
// ▲ UnderWater Ref

// ▼ Side shadow 
const float3 sunPos = (0.25, 1.0, 0.25); // Fake
const float shadowDepth = 0.5;
float3 shadowRs = clamp(0.0, lerp(lerp(shadowDepth, 1.0, dot(normalize(sunPos), normalize(cross(ddx(-PSInput.pos), ddy(-PSInput.pos)))))*1.96, 1.2, PSInput.uv1.x), 1.0);
#if !defined(BLEND) && !defined(ALPHA_TEST)
	diffuse.rgb *= lerp(shadowRs, 1.0, isTop);
#elif defined(ALPHA_TEST)
	if(PSInput.color.g != PSInput.color.b) {
		diffuse.rgb *= shadowRs;
	}
#endif
// 草
diffuse.rgb *= lerp(0.5, 1.0, smoothstep(0.42, 0.6, PSInput.color.g));
// ▲ Side shadow

// ▼ Fog
float isTwilight = clamp((FOG_COLOR.r-0.1)-FOG_COLOR.b,0.0,0.5)*2.0;

const float3 dayFog = float3(0.68, 0.82,0.94)*1.23;// day fog color
const float3 nightFog = float3(-1.0, -1.0, -1.0);// night fog color
const float3 twilightFog = float3(0.75, 0.24, 0.0)*0.47;// dusk & dawn fog color
const float3 rainFog = float3(0.63, 0.8,0.86);//  rain fog color
float3 fogClr = lerp(lerp(lerp(nightFog, dayFog, isDay), twilightFog, isTwilight), rainFog, isRain);

float rainDist = lerp(1.0, 0.23, isRain);
float fog = smoothstep(0.0, RENDER_DISTANCE*0.9*rainDist, length(PSInput.wP));

diffuse.rgb = lerp(diffuse.rgb, fogClr, fog);

diffuse.rgb += lerp(0.0, float3(1.0, 0.31, 0.0)*0.18, isTwilight);
diffuse.r *= 1.19;
// ▲ Fog

/*明度によってハイライト(不採用)
float uv_maxV = 0.5;
if(TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).r > uv_maxV && TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).g > uv_maxV && TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).b > uv_maxV) {diffuse.rgb += float3(1.0, 1.0, -0.5) * max(PSInput.uv1.x-.5, 0.) * smoothstep(2.55, 0.0, (TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).r - uv_maxV) + (TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).g - uv_maxV) + (TEXTURE_0.Sample(TextureSampler0, PSInput.uv0).b - uv_maxV));}
*/


PSOutput.color = diffuse / 1.2;

#ifdef VR_MODE
	// On Rift, the transition from 0 brightness to the lowest 8 bit value is abrupt, so clamp to 
	// the lowest 8 bit value.
	PSOutput.color = max(PSOutput.color, 1 / 255.0f);
#endif

#endif // BYPASS_PIXEL_SHADER
}