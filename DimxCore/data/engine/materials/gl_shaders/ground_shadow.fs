DIMX_FLOAT_PRECISION

// The ground shadow (GroundShadow): black, with the blurred darkness of what
// stands over the ground as its alpha - premultiplied, so the frame behind is
// scaled by 1 - alpha. It lies on the real ground, so whatever real stands in
// front of the ground hides it, in the frames that have the camera's depth.

in vec2 fTexCoord;
in vec4 fPosition;
in vec4 fViewPosition;

uniform sampler2D fGroundShadow;
uniform float fOpacity;

#ifdef USE_DEPTH_FOR_OCCLUSION
#include "depth_occlusion.inc"
#endif

out vec4 outColor;

void main()
{
    float shadow = texture(fGroundShadow, fTexCoord).r * fOpacity;
    if (shadow < 1.0 / 255.0) {
        discard;
    }
#ifdef USE_DEPTH_FOR_OCCLUSION
    if (fUseDepthOcclusion) {
        shadow *= calcOcclusion(fViewPosition, fPosition);
    }
#endif
    outColor = vec4(0.0, 0.0, 0.0, shadow);
}
