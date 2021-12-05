#include "ShaderConstants.fxh"


struct VS_Input
{
    float3 position : POSITION;
    float4 color : COLOR;
#ifdef INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
};


struct PS_Input
{
    float4 position : SV_Position;
    float4 color : COLOR;
	float fog : fog;
	float3 pos : pos;
#ifdef GEOMETRY_INSTANCEDSTEREO
	uint instanceID : SV_InstanceID;
#endif
#ifdef VERTEXSHADER_INSTANCEDSTEREO
	uint renTarget_id : SV_RenderTargetArrayIndex;
#endif
};

ROOT_SIGNATURE
void main(in VS_Input VSInput, out PS_Input PSInput)
{

//Dome sky
float4 psd = float4(VSInput.position,1);
psd.y += -length(psd.xz)*0.278;

float4 skyPos = float4(VSInput.position, 1);

#ifdef INSTANCEDSTEREO
	int i = VSInput.instanceID;
	PSInput.position = mul( WORLDVIEWPROJ_STEREO[i], psd );
#else
	PSInput.position = mul(WORLDVIEWPROJ, psd );
#endif
#ifdef GEOMETRY_INSTANCEDSTEREO
	PSInput.instanceID = VSInput.instanceID;
#endif 
#ifdef VERTEXSHADER_INSTANCEDSTEREO
	PSInput.renTarget_id = VSInput.instanceID;
#endif

PSInput.fog = VSInput.color.r;
PSInput.pos = VSInput.position.xyz;

}