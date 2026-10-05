#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <simd/simd.h>

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger int // TODO: use 32-bit NSInteger.. which is not available
#else
#import <Foundation/Foundation.h>
#endif

#define METAL_MAX_MORPH_TARGETS_BLEND 20

// StandardFragmentUniforms.fBlendMode - the same values Material_effectiveBlend
// answers and the GL shader switches on.
#define BLEND_MODE_OPAQUE   0
#define BLEND_MODE_CUTOUT   1
#define BLEND_MODE_ALPHA    2
#define BLEND_MODE_ADDITIVE 3
#define BLEND_MODE_MULTIPLY 4

struct StandardVertexUniforms {
    matrix_float4x4 vViewMat;
    matrix_float4x4 vViewProjMat;
    matrix_float4x4 vModelMat;
    matrix_float3x3 vNormalMat;

    // Affine texture-coordinate transform, applied as uv' = (M * float3(uv, 1)).xy.
    // Materials that declare a "uvTransform" Mat3 parameter drive it; the rest keep
    // the identity Material seeds it with.
    matrix_float3x3 vUvTransform;

    int   vNumMeshVerts;
    int   vMorphTargetInds[METAL_MAX_MORPH_TARGETS_BLEND];
    float vMorphTargetWeights[METAL_MAX_MORPH_TARGETS_BLEND];
    int   vMorphNumTargets;
    int   vMorphVertComps;
};

//matrix_float4x4 vJointTransforms[196];

struct StandardFragmentUniforms {
    vector_float4 fBaseColor;
    float fBaseColorWeight;
    float fMetalness;
    float fRoughness;

    vector_float4 fAddColor;
    vector_float4 fMultColor;
    
    vector_float3 fCameraPos;
    
    bool fReceiveLighting;

    float fRadianceMaxLod;

    vector_float3 fLightDir;
    vector_float3 fLightAmbientColor;
    vector_float3 fLightDiffuseColor;
    vector_float3 fLightSpecularColor;

    // Occlusion by the real world (Renderer.updateDepthOcclusion): whether this
    // draw is occluded, the transform from screen NDC to the camera image's
    // coordinates - what the depth map (metres) and its matte are laid out in -
    // and the depth map's width over its height.
    bool fUseDepthOcclusion;
    matrix_float3x3 fDepthMapUVTransform;
    float fDepthMapAspectRatio;

    // Render state (see Material.h): how alpha is meant, the cutout threshold,
    // and whether the base colour map's texels are premultiplied by alpha.
    // Mirrors DimxNative/src/ShaderCommon.h, which is what Swift reads.
    int fBlendMode;
    float fAlphaCutoff;
    bool fBaseColorMapPremultiplied;
};

// The ground shadow's quad (GroundShadowPass, GroundShadow.metal): the square
// (u, 0, v) onto the ground region by quadMat, black at opacity times the
// blurred darkness, faded by the real world's depth like the content.
struct GroundShadowUniforms {
    matrix_float4x4 viewProjMat;
    matrix_float4x4 quadMat;
    matrix_float3x3 depthMapUVTransform;
    float opacity;
    float depthMapAspectRatio;
    bool useDepthOcclusion;
};

// One axis of the ground shadow's blur: a tap's step in texture coordinates.
struct GroundShadowBlurUniforms {
    vector_float2 step;
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    vPosition = 0,
    vPosition2,
    vNormal,
    vTangent,
    vBitangent,
    vTexCoord,
    vColor,
    vColorUB,
    vJointIndex,
    vJointIndices4,
    vJointWeights4,
    vNone
};

typedef NS_ENUM(NSInteger, VertexBufferIndex)
{
    VBIVertexBuffer = 0,
    VBIUniforms,
    VBIJointTransforms,
    VBIMorphInds,
    VBIMorphVerts,
};

typedef NS_ENUM(NSInteger, FragmentBufferIndex)
{
    FBIUniforms = 0
};

typedef NS_ENUM(NSInteger, FragmentTextureIndex)
{
    FTIDepthMap = 0,
    FTIIrradianceMap,
    FTIRadianceMap,
    FTIBaseColorMap,
    FTINormalMap,
    FTIMetalnessMap,
    FTIRoughnessMap,
    FTIDepthMatte,
};

typedef NS_ENUM(NSInteger, FunctionConstant)
{
    // VertexAttribute and FunctionConstant must match core VertexAttribType!
    // Vertex attribute constants
    FCPositionAttr = 0,
    FCPosition2Attr,
    FCNormalAttr,
    FCTangentAttr,
    FCBitangentAttr,
    FCTexCoordAttr,
    FCColorAttr,
    FCColorUBAttr,
    FCJointIndexAttr,
    FCJointIndices4Attr,
    FCJointWeights4Attr,
    FCNoneAttr,
    
    // Add other constants below
    FCOcclusionPass,
    FCMorphEnabled,
    FCMorphNormals,
    
    FCBaseColorMap,
    FCNormalMap,
    FCMetalnessMap,
    FCRoughnessMap,

    FCSdfText
};

#endif /* ShaderCommon_h */
