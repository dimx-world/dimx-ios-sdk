
// Occlusion by the AR camera's depth: how much of a fragment the real world
// leaves in sight - 1 with nothing real in front of it, 0 behind a wall. The
// depth map is ARCore's DEPTH16, millimetres along the camera's axis, the low
// byte in red and the high byte in green of an RG8 texture, laid over the
// screen by fDepthMapUVTransform (screen NDC to depth texture). A depth of 0
// is no data and hides nothing, which is what the map holds until the AR
// session hands one over.

uniform bool fUseDepthOcclusion;
uniform sampler2D fDepthMap;
uniform mat3 fDepthMapUVTransform;
uniform float fDepthMapAspectRatio;

// The decode is linear in the two bytes, so the texture's linear filtering
// interpolates the depth itself.
float DepthGetMillimeters(in vec2 depth_uv) {
  vec2 packedDepth = texture(fDepthMap, depth_uv).xy;
  return dot(packedDepth, vec2(255.0, 256.0 * 255.0));
}

// Returns linear interpolation position of value between min and max bounds.
// E.g., DepthInverseLerp(1100, 1000, 2000) returns 0.1.
float DepthInverseLerp(in float value, in float min_bound, in float max_bound) {
  return clamp((value - min_bound) / (max_bound - min_bound), 0.0, 1.0);
}

// Returns a value between 0.0 (not visible) and 1.0 (completely visible)
// Which represents how visible or occluded is the pixel in relation to the
// depth map.
float DepthGetVisibility(in vec2 depth_uv, in float asset_depth_mm) {
  float depth_mm = DepthGetMillimeters(depth_uv);

  // Instead of a hard z-buffer test, allow the asset to fade into the
  // background along a 2 * kDepthTolerancePerMm * asset_depth_mm
  // range centered on the background depth.
  const float kDepthTolerancePerMm = 0.015;
  float visibility_occlusion = clamp(0.5 * (depth_mm - asset_depth_mm) /
    (kDepthTolerancePerMm * asset_depth_mm) + 0.5, 0.0, 1.0);

  // Depth close to zero is most likely invalid, do not use it for occlusions.
  float visibility_depth_near = 1.0 - DepthInverseLerp(
      depth_mm, /*min_depth_mm=*/150.0, /*max_depth_mm=*/200.0);

  // Same for very high depth values.
  float visibility_depth_far = DepthInverseLerp(
      depth_mm, /*min_depth_mm=*/7500.0, /*max_depth_mm=*/8000.0);

  const float kOcclusionAlpha = 0.0;
  float visibility =
      max(max(visibility_occlusion, kOcclusionAlpha),
          max(visibility_depth_near, visibility_depth_far));

  return visibility;
}

// The visibility over the fragment's neighbourhood, so that an edge fades
// rather than steps: a 3x3 tent (1-2-1 by 1-2-1) whose taps stand 1.5 blur
// units apart. ARCore's sample spreads the same footprint over 21 taps; the
// texture's linear filtering smooths between these. The y spacing is scaled by
// the map's aspect ratio, so the kernel covers as many texels down as across.
float DepthGetBlurredVisibilityAroundUV(in vec2 uv, in float asset_depth_mm)
{
  const float kOcclusionBlurAmount = 0.01;
  vec2 d = 1.5 * vec2(kOcclusionBlurAmount, kOcclusionBlurAmount * fDepthMapAspectRatio);

  float sum = 4.0 * DepthGetVisibility(uv, asset_depth_mm);

  sum += 2.0 * (DepthGetVisibility(uv + vec2(+d.x, 0.0), asset_depth_mm)
              + DepthGetVisibility(uv + vec2(-d.x, 0.0), asset_depth_mm)
              + DepthGetVisibility(uv + vec2(0.0, +d.y), asset_depth_mm)
              + DepthGetVisibility(uv + vec2(0.0, -d.y), asset_depth_mm));

  sum += DepthGetVisibility(uv + vec2(+d.x, +d.y), asset_depth_mm)
       + DepthGetVisibility(uv + vec2(-d.x, +d.y), asset_depth_mm)
       + DepthGetVisibility(uv + vec2(+d.x, -d.y), asset_depth_mm)
       + DepthGetVisibility(uv + vec2(-d.x, -d.y), asset_depth_mm);

  return sum / 16.0;
}

// viewPos is the fragment in the camera's space, clipPos in clip space - the
// position as the vertex shader wrote it, divided here rather than there: the
// perspective division does not interpolate linearly across a triangle, and
// on a big one close to the camera, a floor or a wall, a per-vertex division
// sampled the depth map ever further from the fragment.
float calcOcclusion(vec4 viewPos, vec4 clipPos)
{
    const float kMetersToMillimeters = 1000.0;
    float object_depth_mm = viewPos.z * kMetersToMillimeters * -1.;
    vec2 ndc = clipPos.xy / clipPos.w;
    vec2 depth_uvs = (fDepthMapUVTransform * vec3(ndc, 1.0)).xy;
    return DepthGetBlurredVisibilityAroundUV(depth_uvs, object_depth_mm);
}
