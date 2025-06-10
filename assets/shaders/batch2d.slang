struct vertex_info
{
    float3 position : TEXCOORD0;
    float4 color : TEXCOORD1;
    float2 texcoord : TEXCOORD2;
    float2 real_texcoord : TEXCOORD3;               // Real texture coors for sampling, used for texture atlas
    nointerpolation uint texture_index : TEXCOORD4; // Texture index for the vertex
    float4 corner_radius : TEXCOORD5;               // Radius for rounded corners, 0 means no rounded corners
    float border_width : TEXCOORD6;                 // Radius for border, 0 means no border
    float4 border_color : TEXCOORD7;                // RGBA for border color, 0 means no border
    uint flags : TEXCOORD8;                         // Flags for additional information, e.g., whether to discard the pixel
};

static const uint VERTEX_FLAG_TEXTURE_TEXT = 0x1; // Flag to indicate that the vertex uses SDF texture sampling

struct vertex_to_pixel
{
    float4 position : SV_POSITION;
    float4 color : COLOR;
    float2 texcoord : TEXCOORD0;
    float2 real_texcoord : TEXCOORD1;               // Real texture coors for sampling, used for texture atlas
    nointerpolation uint texture_index : TEXCOORD2; // Texture index for the pixel shader
    float4 corner_radius : TEXCOORD3;               // Radius for rounded corners, 0 means no rounded corners
    float border_width : TEXCOORD4;                 // Radius for border, 0 means no border
    float4 border_color : TEXCOORD5;                // RGBA for border color, 0 means no border
    uint flags : TEXCOORD6;                         // Flags for additional information, e.g., whether to discard the pixel
};

struct Constants
{
    row_major float4x4 projection_matrix;
    row_major float4x4 view_matrix;
    row_major float4x4 model_matrix;
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

    OUT.position = mul(float4(IN.position, 1.0), constants.projection_matrix);
    // OUT.position = mul(OUT.position, constants.view_matrix);
    // // OUT.position = mul(OUT.position, constants.model_matrix);

    // use frame buffer size to calculate the position
    // OUT.position = float4(IN.position.xy / constants.viewport_size, IN.position.z, 1.0);

    OUT.color = IN.color;
    OUT.real_texcoord = IN.real_texcoord; // Use real texture coordinates for sampling
    OUT.texcoord = IN.texcoord;
    OUT.texture_index = IN.texture_index;
    OUT.corner_radius = IN.corner_radius;
    OUT.border_width = IN.border_width;
    OUT.border_color = IN.border_color;
    OUT.flags = IN.flags;

    return OUT;
};

/// https://iquilezles.org/articles/distfunctions2d/
float sdRoundedBox(in float2 p, in float2 b, in float4 r)
{
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x = (p.y > 0.0) ? r.x : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

struct fragment_out
{
    float4 color : SV_Target;
};

// mix function

float average(float a, float b, float c)
{
    return (a + b + c) / 3.0f;
}

[shader("fragment")]
fragment_out fragment(in vertex_to_pixel IN)
{
    // sample the texture using the texcoord

    fragment_out OUT;

    float softness = 0.01f;
    float4 texture_pixel = textures[NonUniformResourceIndex(IN.texture_index)].Sample(linear_sampler, float2(IN.real_texcoord.x, IN.real_texcoord.y));
    const bool is_text = (IN.flags & VERTEX_FLAG_TEXTURE_TEXT) != 0; // Check if the vertex uses SDF texture sampling
    float sdf_distance_outside = 0.0f;                               // Initialize SDF distance outside
    if (is_text)
    {
        sdf_distance_outside = 0.5 - average(texture_pixel.r, texture_pixel.g, texture_pixel.b); // Use average of RGB channels for SDF distance
        float2 ddist = float2(ddx(sdf_distance_outside), ddy(sdf_distance_outside));
        float pixel_dist = sdf_distance_outside / length(ddist);
        texture_pixel = float4(1.0, 1.0, 1.0, 1.0); // Set texture pixel to white for SDF textures
        float opacity = saturate(0.5 - sdf_distance_outside);
        if (opacity < 0.01)
            discard;
        OUT.color = float4(IN.color.rgb, IN.color.a * opacity); // Use the calculated opacity for the color

        return OUT; // Return early for SDF textures
    }
    else
    {
        // assume square box for non-SDF textures
        float2 center = IN.texcoord * 2.0 - 1.0; // Convert to range [-1, 1]
        float2 size = float2(1, 1);              // Size of the box
        sdf_distance_outside = sdRoundedBox(center, size, IN.corner_radius);
    }

    float sdf_distance_border = sdf_distance_outside + IN.border_width; // Distance for the border area
    float smoothedAlpha = 1.0f - smoothstep(0.0f, softness * 2.0f, sdf_distance_outside);
    // Outside the rounded box

    if (sdf_distance_outside > 0.0f)
    {
        discard;
    }

    if (sdf_distance_outside + IN.border_width > 0.0f)
    {
        // If inside the border area, return transparent
        // return IN.border_color * smoothedAlpha; // Apply border color with alpha
        OUT.color = IN.border_color * smoothedAlpha; // Apply border color with alpha
        return OUT;
    }

    OUT.color = texture_pixel * IN.color;
    return OUT;
};
