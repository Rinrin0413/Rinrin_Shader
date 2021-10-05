#include "ShaderConstants.fxh"

struct VS_Input {
	float3 position : POSITION;
	float4 color : COLOR;
	float2 uv0 : TEXCOORD_0;
	float2 uv1 : TEXCOORD_1;
#ifdef INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
};


struct PS_Input {
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
#ifdef GEOMETRY_INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
#ifdef VERTEXSHADER_INSTANCEDSTEREO
	uint renTarget_id : SV_RenderTargetArrayIndex;
#endif
};


static const float rA = 1.0;
static const float rB = 1.0;
static const float3 UNIT_Y = float3(0, 1, 0);
static const float DIST_DESATURATION = 56.0 / 255.0; //WARNING this value is also hardcoded in the water color, don'tchange

// ▼ rand
float hash11(float p) {
	p = frac(p * .1031);
	p *= p + 33.33;
	p *= p + p;
	return frac(p);
}
float rand(float3 p) {
	float x = (p.x + p.y + p.z)/3.0 + TOTAL_REAL_WORLD_TIME;
	return lerp(hash11(floor(x)),hash11(ceil(x)),smoothstep(0.0,1.0,frac(x)))*2.0;
}
// ▲ rand

// ▼ plant?
bool isPlants(float3 vertexColor, float3 chunkedPosition) {
    float3 fractedChunkedPosition = frac(chunkedPosition.xyz);
    #if defined(ALPHA_TEST)
        return (vertexColor.g != vertexColor.b && vertexColor.r < vertexColor.g + vertexColor.b) || (fractedChunkedPosition.y == 0.9375 && (fractedChunkedPosition.z == 0.0 || fractedChunkedPosition.x == 0.0));
    #else
        return false;
    #endif
}
// ▼ plant?

ROOT_SIGNATURE
void main(in VS_Input VSInput, out PS_Input PSInput)
{
PSInput.waterFlag = 0.0;
PSInput.pos = VSInput.position.xyz;
#ifndef BYPASS_PIXEL_SHADER
	PSInput.uv0 = VSInput.uv0;
	PSInput.uv1 = VSInput.uv1;
	PSInput.color = VSInput.color;
#endif

#ifdef AS_ENTITY_RENDERER
	#ifdef INSTANCEDSTEREO
		int i = VSInput.instanceID;
		PSInput.position = mul(WORLDVIEWPROJ_STEREO[i], float4(VSInput.position, 1));
	#else
		PSInput.position = mul(WORLDVIEWPROJ, float4(VSInput.position, 1));
	#endif
		float3 worldPos = PSInput.position;
#else
		float3 worldPos = (VSInput.position.xyz * CHUNK_ORIGIN_AND_SCALE.w) + CHUNK_ORIGIN_AND_SCALE.xyz;
	// ▼ お水揺れろworldPos.xyz
	float3 kamiPos = abs(VSInput.position.xyz - 8.0);
	#ifdef BLEND
	if(VSInput.color.b > VSInput.color.r) {
    	worldPos.y -= cos(kamiPos.x * 2.0 + kamiPos.y * 2.0 + kamiPos.z * 2.0 + TOTAL_REAL_WORLD_TIME * 2.0)  * rand(kamiPos) * 0.05;
	}
	#endif
	if (FOG_CONTROL.x == 0.0) { // UnderWater
		worldPos.xz -= cos(kamiPos.x * 2.5 + kamiPos.y * 1.8 + kamiPos.z * 2.5 + TOTAL_REAL_WORLD_TIME * 1.9) * 0.027;
	}
	// ▲ お水揺れろ
	// ▼ Waving Plants
	if(isPlants(VSInput.color.rgb, VSInput.position.xyz)) {
		worldPos.x += sin(kamiPos.x * 2.5 + kamiPos.y * 0.9 + kamiPos.z * 2.2 + TOTAL_REAL_WORLD_TIME * 2.0) * lerp(0.2,1,smoothstep(0.78, 0.90, VSInput.uv1.y)) * rand(VSInput.position) * 0.023;
	}
	// ▲ Waving Plants

		// Transform to view space before projection instead of all at once to avoid floating point errors
		// Not required for entities because they are already offset by camera translation before rendering
		// World position here is calculated above and can get huge
	#ifdef INSTANCEDSTEREO
		int i = VSInput.instanceID;
	
		PSInput.position = mul(WORLDVIEW_STEREO[i], float4(worldPos, 1 ));
		PSInput.position = mul(PROJ_STEREO[i], PSInput.position);
	
	#else
		PSInput.position = mul(WORLDVIEW, float4( worldPos, 1 ));
		PSInput.position = mul(PROJ, PSInput.position);
	#endif
PSInput.wP = worldPos;
#endif
#ifdef GEOMETRY_INSTANCEDSTEREO
		PSInput.instanceID = VSInput.instanceID;
#endif 
#ifdef VERTEXSHADER_INSTANCEDSTEREO
		PSInput.renTarget_id = VSInput.instanceID;
#endif
///// find distance from the camera

#if defined(FOG) || defined(BLEND)
	#ifdef FANCY
		float3 relPos = -worldPos;
		float cameraDepth = length(relPos);
	#else
		float cameraDepth = PSInput.position.z;
	#endif
#endif

	///// apply fog

#ifdef FOG
	float len = cameraDepth / RENDER_DISTANCE;
#ifdef ALLOW_FADE
	len += RENDER_CHUNK_FOG_ALPHA.r;
#endif

	PSInput.fogColor.rgb = FOG_COLOR.rgb;
	PSInput.fogColor.a = clamp((len - FOG_CONTROL.x) / (FOG_CONTROL.y - FOG_CONTROL.x), 0.0, 1.0);

#endif



///// blended layer (mostly water) magic
#ifdef BLEND
	//Mega hack: only things that become opaque are allowed to have vertex-driven transparency in the Blended layer...
	//to fix this we'd need to find more space for a flag in the vertex format. color.a is the only unused part
	bool shouldBecomeOpaqueInTheDistance = VSInput.color.a < 0.95;
	if(shouldBecomeOpaqueInTheDistance) {
		#ifdef FANCY  /////enhance water
			float cameraDist = cameraDepth / FAR_CHUNKS_DISTANCE;
		#else
			float3 relPos = -worldPos.xyz;
			float camDist = length(relPos);
			float cameraDist = camDist / FAR_CHUNKS_DISTANCE;
		#endif //FANCY
		
		float alphaFadeOut = clamp(cameraDist, 0.0, 1.0);
		PSInput.color.a = lerp(VSInput.color.a, 1.0, alphaFadeOut);
		PSInput.waterFlag = 1.0;
	}
#endif

}
