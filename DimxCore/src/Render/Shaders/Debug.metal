#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position  [[attribute(0)]];
    float4 color     [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut debug_vertex(VertexIn in                    [[stage_in]],
                              constant float4x4 &viewProjMat [[buffer(1)]])
{
    VertexOut out;
    out.position = viewProjMat * float4(in.position, 1);
    out.color = in.color;
    return out;
}

fragment half4 debug_fragment(VertexOut in [[stage_in]])
{
    return half4(in.color);
};

// The dots (RenderLines::drawDot): a vertex each, drawn as a point of the list's dot size in pixels.
struct PointOut {
    float4 position [[position]];
    float4 color;
    float size [[point_size]];
};

vertex PointOut debug_point_vertex(VertexIn in                    [[stage_in]],
                                   constant float4x4 &viewProjMat [[buffer(1)]],
                                   constant float &pointSize      [[buffer(2)]])
{
    PointOut out;
    out.position = viewProjMat * float4(in.position, 1);
    out.color = in.color;
    out.size = pointSize;
    return out;
}

// The geometry held across frames (RenderLines::setSurface, addCloud): the same vertices, in the
// piece's own frame, at the opacity it is drawn at over its vertices' own alpha - a surface's
// triangles, or a cloud's points of the cloud's own size.
vertex VertexOut debug_held_vertex(VertexIn in                     [[stage_in]],
                                   constant float4x4 &mvpMat       [[buffer(1)]],
                                   constant float &opacity         [[buffer(2)]])
{
    VertexOut out;
    out.position = mvpMat * float4(in.position, 1);
    out.color = float4(in.color.rgb, in.color.a * opacity);
    return out;
}

vertex PointOut debug_held_point_vertex(VertexIn in                     [[stage_in]],
                                        constant float4x4 &mvpMat       [[buffer(1)]],
                                        constant float &opacity         [[buffer(2)]],
                                        constant float &pointSize       [[buffer(3)]])
{
    PointOut out;
    out.position = mvpMat * float4(in.position, 1);
    out.color = float4(in.color.rgb, in.color.a * opacity);
    out.size = pointSize;
    return out;
}

// The pictures (RenderLines::drawTexturedQuad): premultiplied out at the quad's opacity, for the
// ONE / ONE_MINUS_SRC_ALPHA blend - the GL pass's debug_tex.fs.
struct QuadIn {
    float3 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadOut debug_quad_vertex(QuadIn in                     [[stage_in]],
                                 constant float4x4 &viewProjMat [[buffer(1)]])
{
    QuadOut out;
    out.position = viewProjMat * float4(in.position, 1);
    out.uv = in.uv;
    return out;
}

// params: the quad's opacity, and 1 when the texture's colour is multiplied by its alpha
// already (an SVG tile) - not multiplied again; a straight-alpha picture is multiplied here.
fragment half4 debug_quad_fragment(QuadOut in               [[stage_in]],
                                   texture2d<float> picture  [[texture(0)]],
                                   sampler pictureSampler    [[sampler(0)]],
                                   constant float2 &params   [[buffer(0)]])
{
    const float4 color = picture.sample(pictureSampler, in.uv);
    const float a = color.a * params.x;
    return half4(half3(color.rgb * (params.y > 0.5 ? params.x : a)), half(a));
}
