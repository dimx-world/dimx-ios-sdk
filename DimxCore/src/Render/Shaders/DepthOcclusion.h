#ifndef DepthOcclusion_h
#define DepthOcclusion_h

#include <metal_stdlib>
using namespace metal;

// Occlusion by the real world: how much of a fragment the camera's depth leaves
// in sight (Renderer.updateDepthOcclusion; depth_occlusion.inc is the GL
// renderer's). depthMap holds metres along the camera's axis, 0 where there is
// no depth - which hides nothing - and depthMatte how much of each texel that
// depth stands for: 1 everywhere for LiDAR's scene depth, the person matte for
// people occlusion, whose depth is only where a person is. Inline: every .metal
// file that includes it - Standard.metal, GroundShadow.metal - gets its own.
inline float depthVisibility(texture2d<float, access::sample> depthMap,
                             texture2d<half, access::sample> depthMatte,
                             float2 uv, float assetMM)
{
    // Nearest for the depth: a 32-bit float texture is not filterable on every
    // iPhone, and the kernel around it smooths the edge anyway.
    constexpr sampler depthSampler(address::clamp_to_edge, filter::nearest);
    constexpr sampler matteSampler(address::clamp_to_edge, filter::linear);
    float depthMM = depthMap.sample(depthSampler, uv).r * 1000.0;
    float matte = float(depthMatte.sample(matteSampler, uv).r);

    // Not a hard depth test: the asset fades into the background along
    // 2 * kDepthTolerancePerMM of its depth, centred on the background's.
    constexpr float kDepthTolerancePerMM = 0.015;
    float visible = clamp(0.5 * (depthMM - assetMM) / (kDepthTolerancePerMM * assetMM) + 0.5, 0.0, 1.0);
    // A depth near zero is no data, and the far end of the range is no better.
    float visibleNear = 1.0 - clamp((depthMM - 150.0) / 50.0, 0.0, 1.0);
    float visibleFar = clamp((depthMM - 7500.0) / 500.0, 0.0, 1.0);
    visible = max(visible, max(visibleNear, visibleFar));

    return mix(1.0, visible, matte);
}

// 1 unless `use`; then the visibility over the fragment's neighbourhood, so
// that an edge fades rather than steps - a 3x3 tent of taps 1.5 blur units
// apart, as depth_occlusion.inc. `clipPos` is the position in clip space as the
// vertex stage wrote it: divided here, per fragment, because the perspective
// division does not interpolate linearly across a triangle.
inline float calcOcclusionAt(float4 clipPos,
                             bool use,
                             float3x3 uvTransform,
                             float aspectRatio,
                             texture2d<float, access::sample> depthMap,
                             texture2d<half, access::sample> depthMatte)
{
    if (!use) {
        return 1.0;
    }
    float2 ndc = clipPos.xy / clipPos.w;
    float2 uv = (uvTransform * float3(ndc, 1.0)).xy;
    // A perspective projection's clip-space w is the depth along the camera's axis.
    float assetMM = clipPos.w * 1000.0;

    constexpr float kBlur = 1.5 * 0.01;
    float2 d = float2(kBlur, kBlur * aspectRatio);

    float sum = 4.0 * depthVisibility(depthMap, depthMatte, uv, assetMM);
    sum += 2.0 * (depthVisibility(depthMap, depthMatte, uv + float2(+d.x, 0.0), assetMM)
                + depthVisibility(depthMap, depthMatte, uv + float2(-d.x, 0.0), assetMM)
                + depthVisibility(depthMap, depthMatte, uv + float2(0.0, +d.y), assetMM)
                + depthVisibility(depthMap, depthMatte, uv + float2(0.0, -d.y), assetMM));
    sum += depthVisibility(depthMap, depthMatte, uv + float2(+d.x, +d.y), assetMM)
         + depthVisibility(depthMap, depthMatte, uv + float2(-d.x, +d.y), assetMM)
         + depthVisibility(depthMap, depthMatte, uv + float2(+d.x, -d.y), assetMM)
         + depthVisibility(depthMap, depthMatte, uv + float2(-d.x, -d.y), assetMM);
    return sum / 16.0;
}

#endif /* DepthOcclusion_h */
