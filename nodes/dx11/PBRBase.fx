//@author: microdee
//@help: Anisotropic IBL
//@tags: IBL PBR
//@credits:


#define DISCSAMPLES 4
#define DIFFENVSRC Environment

#include <packs/mp.fxh/AnisotropicEnvSample.fxh>
#include <packs/mp.fxh/DiscSample.fxh>
#include <packs/mp.fxh/bitwise.fxh>
#if !defined(UVLAYER)
#define UVLAYER TEXCOORD0
#endif

//#define DO_VELOCITY 1

StructuredBuffer<float4x4> Tr <string uiname="Transforms";>;
StructuredBuffer<float4x4> pTr <string uiname="Previous Transforms";>;
StructuredBuffer<float4> AlbedoCol;
StructuredBuffer<float> TexID;
Texture2DArray Albedo;
Texture2DArray NormBump;
Texture2D DispMap;
//Texture2D DiffEnv;

struct VSin
{
    float3 Pos : POSITION;
    float3 Norm : NORMAL;
    float2 UV : UVLAYER;
    #if defined(HAS_TANGENT)
    float3 Tan : TANGENT;
    float3 Bin : BINORMAL;
    #endif
    #if defined(HAS_PREVPOS)
    float3 ppos : PREVPOS;
    #endif
    #if defined(HAS_SUBSETID)
    float sid : SUBSETID;
    #endif
    uint iid : SV_InstanceID;
};

struct PSin
{
    float4 svpos : SV_Position;
	float4 pspos : POSPROJ;
    float3 posw : POSWORLD;
    float3 Norm : NORMAL;
    float2 UV : TEXCOORD0;
    #if defined(HAS_TANGENT)
    float3 Tan : TANGENT;
    float3 Bin : BINORMAL;
    #endif
    float4 ppos : PREVPOS;
    nointerpolation float sid : SUBSETID;
};

struct PSout
{
    float4 Lit : SV_Target0;
    float4 Norm : SV_Target1;
    float4 VelUV : SV_Target2;
	#if defined(TANTARGETS)
    float4 Tan : SV_Target3;
    float4 Bin : SV_Target4;
	#endif
};

SamplerState sT <string uiname="Textures Sampler";>
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;
    AddressV = Wrap;
};

cbuffer cbPerDraw : register(b0)
{
	float4x4 tV : VIEW;
	float4x4 tVI : VIEWINVERSE;
    float4x4 tP : PROJECTION;
    float4x4 ptV : PREVIOUSVIEW;
    float4x4 ptP : PREVIOUSPROJECTION;
};

cbuffer cbPerObj : register( b1 )
{
	float4x4 tW : WORLD;
    float4x4 ptW <string uiname="Previous World";>;
    float4x4 tTex <string uiname="Texture Transforms";>;
    float4x4 ptTex <string uiname="Previous Texture Transforms";>;
    float ndepth <string uiname="Normal Depth";> = 0;
	float2 Displace = 0;
};
PSin VS(VSin input)
{
	PSin output;
    uint ii = input.iid;
    #if defined(HAS_SUBSETID)
    ii = input.sid;
    #endif
    output.sid = ii;
	
    output.UV = mul(float4(input.UV, 0, 1), tTex).xy;
    float2 puv = mul(float4(input.UV, 0, 1), ptTex).xy;

    float4x4 w = mul(Tr[ii], tW);
	
    float4x4 tWV = mul(w, tV);
    output.Norm = normalize(mul(float4(input.Norm,0), tWV).xyz);
	
	float3 posi = input.Pos + DispMap.SampleLevel(sT, output.UV, 0).r * input.Norm * Displace.x;
	output.svpos = mul(float4(posi,1), w);
    output.posw = output.svpos.xyz;
	output.svpos = mul(output.svpos, tV);
	output.svpos = mul(output.svpos, tP);
	output.pspos = output.svpos;

    #if defined(HAS_TANGENT)
    output.Tan = normalize(mul(float4(input.Tan,0), tWV).xyz);
    output.Bin = normalize(mul(float4(input.Bin,0), tWV).xyz);
	#endif

    float3 pp = input.Pos;
    #if defined(HAS_PREVPOS)
    pp = input.ppos;
    #endif
	pp += DispMap.SampleLevel(sT, output.UV, 0).g * input.Norm * Displace.y;

    float4x4 pw = mul(pTr[ii], ptW);
	output.ppos = mul(float4(pp,1), pw);
	output.ppos = mul(output.ppos, ptV);
    #if defined(HAS_TANGENT)
    output.ppos.xyz += output.Tan * (output.UV.x-puv.x);
    output.ppos.xyz += output.Bin * (output.UV.y-puv.y);
	#endif
	output.ppos = mul(output.ppos, ptP);

	return output;
}

#if defined(FLATNORMALS)
[maxvertexcount(3)]
void GS(triangle PSin input[3], inout TriangleStream<PSin> gsout)
{
	float3 f1 = input[1].posw.xyz - input[0].posw.xyz;
    float3 f2 = input[2].posw.xyz - input[0].posw.xyz;
    
	//Compute flat normal
	float3 norm = normalize(cross(f1, f2));
	norm = mul(float4(norm, 0), tV).xyz;
	PSin o = (PSin)0;
	for(uint i=0; i<3; i++)
	{
		o = input[i];
		o.Norm = norm;
		gsout.Append(o);
	}
	gsout.RestartStrip();
}
#endif

PSout PS(PSin input)
{
    PSout o = (PSout)0;
    float ii = input.sid;
	float ti = TexID[ii];
    float4 col = AlbedoCol[ii] * Albedo.Sample(sT, float3(input.UV, ti));
    #if defined(HAS_TANGENT)
	float3 normmap = NormBump.Sample(sT, float3(input.UV, ti)).xyz*2-1;
    normmap = lerp(float3(0,0,1), normmap, ndepth);
	float3 norm = normalize(normmap.x * input.Tan + normmap.y * input.Bin + normmap.z * input.Norm);
    float3x3 tanspace = float3x3(
        input.Tan,
        input.Bin,
        input.Norm
    );
	tanspace = transpose(tanspace);
	#else
	float3 norm = input.Norm;
	#endif
	if(dot(norm, float3(0,0,1)) > 0) norm = -norm;

    o.Lit = col;
    o.Norm = float4(norm*0.5+0.5, ii);
	#if defined(TANTARGETS)
	o.Tan.rgb = input.Tan*0.5+0.5;
	o.Bin.rgb = input.Bin*0.5+0.5;
	#endif
    o.VelUV = float4((input.pspos.xy / input.pspos.w) - (input.ppos.xy / input.ppos.w)+0.5, input.UV);
    //o.VelUV = float4(0.5, 0.5, input.UV);

    return o;
}

technique11 AnisotropicIBL
{
	pass P0
	{
		SetVertexShader( CompileShader( vs_5_0, VS() ) );
#if defined(FLATNORMALS)
		SetGeometryShader( CompileShader( gs_5_0, GS() ) );
#endif
		SetPixelShader( CompileShader( ps_5_0, PS() ) );
	}
}
