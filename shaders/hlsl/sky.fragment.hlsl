#include "ShaderConstants.fxh"

struct PS_Input
{
    float4 position : SV_Position;
    float4 color : COLOR;
    float fog : fog;
    float3 pos : pos;
};

struct PS_Output
{
    float4 color : SV_Target;
};

// ▼ Hash, Noise, FBM Functions
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
// ▲ Hash, Noise, FBM Functions

ROOT_SIGNATURE
void main(in PS_Input PSInput, out PS_Output PSOutput)
{

float4 diffuse = CURRENT_COLOR;

float dayLight = saturate(CURRENT_COLOR.b + CURRENT_COLOR.g);
float rain = bool(step(FOG_CONTROL.x, 0.0)) ? 0.0 : smoothstep(0.5, 0.4, FOG_CONTROL.x);// With the exception of Underwater

// ▼ Sky color
const float3 daySky = float3(0.5647058823529412, 0.796078431372549, 0.9822222222222222);// Day sky color
const float3 nightSky = float3(0.19607843137254902, 0.0, 0.3176470588235294);// Night Sky color
const float3 rainSky = float3(0.35, 0.35, 0.35);// Sky color when in rains
float3 skyColor = lerp(lerp(nightSky, daySky, dayLight), rainSky + lerp(nightSky, daySky, dayLight)/3.0, rain);
// ▲ Sky color

// ▼ Cloud color
const float3 dayCloud = float3(0.85, 0.9, 1.0) + 0.15;// Day cloud color
const float3 nightCloud = float3(0.7764705882352941, 0.7019607843137254, 1.0) - 0.4;// Night cloud color
const float3 rainCloud  = float3(0.7, 0.7, 0.7);// Rain cloud color
float3 cloudColor = lerp(lerp(nightCloud, dayCloud, dayLight),rainCloud , rain);
// ▲ cloud color

// ▼ Rendering clouds
float cloudLower = lerp(0.4, 0.1, rain);// Deepen clouds when it rains
float cloud = fbm(PSInput.pos.xz * 5.7);// Shape of clouds
diffuse.rgb = lerp(skyColor, cloudColor, smoothstep(cloudLower, 0.77, cloud));
// ▲ Rendering clouds
    
PSOutput.color = lerp( diffuse, FOG_COLOR, PSInput.fog );

}
