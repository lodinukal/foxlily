struct vertex_info
{
    float3 position : TEXCOORD0;
    float3 color : TEXCOORD1;
    float2 texcoord : TEXCOORD2;
    nointerpolation uint texture_index : TEXCOORD3; // Texture index for the vertex
};

struct vertex_to_pixel
{
    float4 position : SV_POSITION;
    float3 color : COLOR;
    float2 texcoord : TEXCOORD0;
    nointerpolation uint texture_index : TEXCOORD1; // Texture index for the pixel shader
};

struct Constants
{
    float4x4 projection_matrix;
    float4x4 view_matrix;
    float4x4 model_matrix;
    float2 viewport_size;
};

#define MAX_TEXTURES 2048

// main set 0
SamplerState linear_sampler : register(s0, space0);
Texture2D textures[MAX_TEXTURES] : register(t1, space0); // Adjust size based on actual needs

// shared constants 1
ConstantBuffer<Constants> constants : register(b0, space1);

[shader("vertex")]
vertex_to_pixel vertex(in vertex_info IN, uint id: SV_VertexID)
{
    vertex_to_pixel OUT;

    // OUT.position = mul(float4(IN.position, 1.0), constants.projection_matrix);
    // OUT.position = mul(OUT.position, constants.view_matrix);
    // OUT.position = mul(OUT.position, constants.model_matrix);

    // use viewport size for position transformation
    OUT.position = mul(float4(IN.position, 1.0), constants.projection_matrix);

    OUT.color = IN.color;
    OUT.texcoord = IN.texcoord;
    OUT.texture_index = IN.texture_index;

    return OUT;
};

float roundedBoxSDF(float2 center, float2 size, float radius)
{
    return length(max(abs(center) - size + radius, 0.0)) - radius;
}

[shader("fragment")]
float4 fragment(in vertex_to_pixel IN) : SV_TARGET
{
    // sample the texture using the texcoord

    float softness = 0.01f;
    // rounded box SDF example
    float2 center = IN.texcoord * 2.0 - 1.0; // Convert to range [-1, 1]
    float2 size = float2(1, 1);              // Size of the box
    float radius = 0.25;                     // Radius for the rounded corners
    float sdf_distance = roundedBoxSDF(center, size, radius);
    float smoothedAlpha = 1.0f - smoothstep(0.0f, softness * 2.0f, sdf_distance);
    // Outside the rounded box

    // return float4(IN.color, smoothedAlpha);
    float4 texture_pixel = textures[NonUniformResourceIndex(IN.texture_index)].Sample(linear_sampler, float2(IN.texcoord.x, 1.0 - IN.texcoord.y));
    return float4(texture_pixel.xyz * IN.color, smoothedAlpha);
    // return float4(IN.color, smoothedAlpha);

    // return float4(0.0, 0.0, 0.0, 0.0); // Transparent

    // return float4(IN.color, 1.0);
};
