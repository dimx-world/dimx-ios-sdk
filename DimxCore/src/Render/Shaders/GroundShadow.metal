#include <metal_stdlib>

#include "ShaderCommon.h"
#include "DepthOcclusion.h"

using namespace metal;

// The ground shadow (GroundShadow, GroundShadowPass): the blur of what the
// casters look like from below, and the quad that lays it on the ground. The
// GL renderer's are ground_shadow_blur.vs/.fs and ground_shadow.vs/.fs.

struct GroundShadowBlurOut {
    float4 position [[position]];
    float2 texCoord;
};

// One triangle over the whole target - (-1,-1), (3,-1), (-1,3) - from the vertex
// index alone. Metal's texture rows run down from the top while its clip space
// runs up: the coordinate is that of the texel the fragment writes.
vertex GroundShadowBlurOut ground_shadow_blur_vertex(uint vid [[vertex_id]])
{
    float2 pos = float2(float((vid << 1) & 2), float(vid & 2)) * 2.0 - 1.0;
    GroundShadowBlurOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

// exp(-k * k / 8) for k = 0..4: a Gaussian whose sigma is two taps.
constant float kBlurWeights[5] = {1.0, 0.8824969, 0.6065307, 0.3246525, 0.1353353};
constant float kBlurTotal = 4.8980308;

// The first axis: from the casters' depth - their height above the ground over
// the fade height, 1 where nothing casts - to darkness, 1 - depth.
fragment half4 ground_shadow_blur_depth_fragment(GroundShadowBlurOut in [[stage_in]],
                                                 constant GroundShadowBlurUniforms& uniforms [[buffer(0)]],
                                                 depth2d<float, access::sample> source [[texture(0)]])
{
    constexpr sampler pointSampler(address::clamp_to_edge, filter::nearest);
    float sum = kBlurWeights[0] * (1.0 - source.sample(pointSampler, in.texCoord));
    for (int k = 1; k < 5; ++k) {
        float2 d = uniforms.step * float(k);
        sum += kBlurWeights[k] * ((1.0 - source.sample(pointSampler, in.texCoord + d))
                                + (1.0 - source.sample(pointSampler, in.texCoord - d)));
    }
    return half4(half(sum / kBlurTotal), 0.0h, 0.0h, 1.0h);
}

// The second axis, over the first's darkness.
fragment half4 ground_shadow_blur_fragment(GroundShadowBlurOut in [[stage_in]],
                                           constant GroundShadowBlurUniforms& uniforms [[buffer(0)]],
                                           texture2d<half, access::sample> source [[texture(0)]])
{
    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
    float sum = kBlurWeights[0] * float(source.sample(linearSampler, in.texCoord).r);
    for (int k = 1; k < 5; ++k) {
        float2 d = uniforms.step * float(k);
        sum += kBlurWeights[k] * (float(source.sample(linearSampler, in.texCoord + d).r)
                                + float(source.sample(linearSampler, in.texCoord - d).r));
    }
    return half4(half(sum / kBlurTotal), 0.0h, 0.0h, 1.0h);
}

struct GroundShadowOut {
    float4 position [[position]];
    float2 texCoord;
    // The position in clip space, as written, for the real world's depth.
    float4 clipPos;
};

// The square (u, 0, v), u and v from 0 to 1, onto the ground region - from the
// vertex index as a strip, (0,0) (0,1) (1,0) (1,1), counter-clockwise seen from
// above.
vertex GroundShadowOut ground_shadow_vertex(uint vid [[vertex_id]],
                                            constant GroundShadowUniforms& uniforms [[buffer(0)]])
{
    float2 uv = float2(float(vid >> 1), float(vid & 1));
    float4 worldPos = uniforms.quadMat * float4(uv.x, 0.0, uv.y, 1.0);
    GroundShadowOut out;
    out.position = uniforms.viewProjMat * worldPos;
    // A hair towards the camera, so that an occluder standing for the real
    // floor at the same height does not hide it.
    out.position.z -= (1.0 / 8192.0) * abs(out.position.w);
    out.clipPos = out.position;
    // The target's rows run down from the top, the region's v up it.
    out.texCoord = float2(uv.x, 1.0 - uv.y);
    return out;
}

// Black, with the blurred darkness as alpha - premultiplied, so the frame behind
// is scaled by 1 - alpha. It lies on the real ground, so whatever real stands in
// front of the ground hides it, in the frames that have the camera's depth.
fragment float4 ground_shadow_fragment(GroundShadowOut in [[stage_in]],
                                       constant GroundShadowUniforms& uniforms [[buffer(0)]],
                                       texture2d<half, access::sample> shadow [[texture(0)]],
                                       texture2d<float, access::sample> depthMap [[texture(1)]],
                                       texture2d<half, access::sample> depthMatte [[texture(2)]])
{
    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
    float alpha = float(shadow.sample(linearSampler, in.texCoord).r) * uniforms.opacity;
    if (alpha < 1.0 / 255.0) {
        discard_fragment();
    }
    alpha *= calcOcclusionAt(in.clipPos, uniforms.useDepthOcclusion, uniforms.depthMapUVTransform,
                             uniforms.depthMapAspectRatio, depthMap, depthMatte);
    return float4(0.0, 0.0, 0.0, alpha);
}
