struct vertex_info
{
    float3 position : TEXCOORD0;
    float3 color : TEXCOORD1;
    float2 texcoord : TEXCOORD2;
};

struct vertex_to_pixel
{
    float4 position : SV_POSITION;
    float3 color : COLOR;
    float2 texcoord : TEXCOORD0;
};

#define MAX_TEXTURES 2048

StructuredBuffer<uint> a : register(t0, space0);
StructuredBuffer<uint> b : register(t1, space0);
StructuredBuffer<uint> c : register(t2, space0);
SamplerState in_sampler : register(s3, space0);
Texture2D textures[MAX_TEXTURES] : register(t4, space0); // Adjust size based on actual needs

[shader("vertex")]
vertex_to_pixel vertex(in vertex_info IN, uint id: SV_VertexID)
{
    vertex_to_pixel OUT;

    OUT.position = float4(IN.position, 1.0);
    OUT.color = IN.color;
    OUT.texcoord = IN.texcoord;

    return OUT;
};

[shader("fragment")]
float4 fragment(in vertex_to_pixel IN) : SV_TARGET
{
    uint texture_index = 0;
    // sample the texture using the texcoord

    // return sample(textures[texture_index], IN.texcoord);
    return textures[texture_index].Sample(in_sampler, float2(IN.texcoord.x, 1.0 - IN.texcoord.y));
    // return float4(IN.texcoord, 0.0, 1.0); // Placeholder for texture sampling

    // return float4(IN.color, 1.0);
};
