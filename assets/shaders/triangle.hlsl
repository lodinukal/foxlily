struct vertex_info
{
    float3 position : TEXCOORD0;
    float3 color : TEXCOORD1;
};

struct vertex_to_pixel
{
    float4 position : SV_POSITION;
    float3 color : COLOR;
};

vertex_to_pixel vertex(in vertex_info IN, uint id : SV_VertexID)
{
    vertex_to_pixel OUT;

    OUT.position = float4(IN.position, 1.0);
    OUT.color = IN.color;

    return OUT;
};

float4 fragment(in vertex_to_pixel IN) : SV_TARGET
{
    return float4(IN.color, 1.0);
};