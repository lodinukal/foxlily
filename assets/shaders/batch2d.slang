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

static const uint VERTEX_FLAG_TEXTURE_MSDF = 0x1; // Flag to indicate that the vertex uses SDF texture sampling

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
    float depth : SV_Depth; // Depth value for the fragment, if needed
};

// mix function

float median(float r, float g, float b)
{
    return max(min(r, g), min(max(r, g), b));
}

[shader("fragment")]
fragment_out fragment(in vertex_to_pixel IN)
{
    // sample the texture using the texcoord

    fragment_out OUT;
    OUT.depth = IN.position.z / IN.position.w; // Calculate depth value for the fragment

    float softness = 0.01f;
    float4 texture_pixel = textures[NonUniformResourceIndex(IN.texture_index)].Sample(linear_sampler, float2(IN.real_texcoord.x, IN.real_texcoord.y));
    const bool is_msdf = (IN.flags & VERTEX_FLAG_TEXTURE_MSDF) != 0; // Check if the vertex uses SDF texture sampling

    float x = 0.0;
    float edges[4] = { 0.0, 0.0, 0.0, 0.0 };
    float edge_feather = 0.01f; // Feathering for the edges

    const float border_width = max(IN.border_width, 0.0); // Ensure border width is non-negative
    float4 color = IN.color;
    float4 border_color = border_width == 0.0 ? IN.color : IN.border_color;

    if (is_msdf)
    {
        float sdf_distance_outside = 0.5 - median(texture_pixel.r, texture_pixel.g, texture_pixel.b); // Use average of RGB channels for SDF distance
        const float px_range = 2.0;
        float screen_px_range = 72 / 32 * px_range;
        float screen_pixel_dist = screen_px_range * (sdf_distance_outside);

        // in pixels
        edge_feather = 1.5;

        edges[0] = 0.5;
        x = screen_pixel_dist;
    }
    else
    {
        float sdf_distance_outside = sdRoundedBox(IN.texcoord * 2.0 - 1.0, float2(1.0, 1.0), IN.corner_radius);

        // Arbitrary idk
        edge_feather = 0.01f;
        color *= texture_pixel; // Use the texture color for the main color

        edges[0] = 0.0 - edge_feather - border_width;
        x = sdf_distance_outside;
    }

    edges[1] = edges[0] + edge_feather;
    edges[2] = edges[1] + border_width;
    edges[3] = edges[2] + edge_feather;

    if (x < edges[0])
    {
        OUT.color = color;
    }
    else if (x < edges[1])
    {
        OUT.color = lerp(color, border_color, (x - edges[0]) / (edges[1] - edges[0]));
    }
    else if (x < edges[2])
    {
        OUT.color = border_color;
    }
    else if (x < edges[3])
    {
        float opacity = 1.0 - (x - edges[2]) / (edges[3] - edges[2]);
        OUT.color = border_color;
        OUT.color.a *= opacity; // Apply opacity to the color
    }
    else
    {
        discard;
    }

    return OUT;
};
