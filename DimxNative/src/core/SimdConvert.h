#ifndef SIMD_CONVERT_H_INCLUDED
#define SIMD_CONVERT_H_INCLUDED

#include <simd/simd.h>
#include <CommonMath.h>

// Conversions for the core math types whose glm layout does not match the simd one
// the Swift/Metal side uses. Everything crossing the C interface as a simd type goes
// through here, so the interface signature says which layout the caller gets.
//
// Mat4 (64 bytes) and Vec4 (16) are laid out identically in both worlds and still
// cross by memcpy. Mat3 does NOT: glm packs it as three tightly-packed vec3 columns
// (36 bytes) while simd pads every column out to four floats (48), so copying the
// raw bytes shifts columns 1 and 2 into the wrong lanes.

inline simd_float3x3 toSimd(const Mat3& mat)
{
    return simd_matrix(simd_make_float3(mat[0][0], mat[0][1], mat[0][2]),
                       simd_make_float3(mat[1][0], mat[1][1], mat[1][2]),
                       simd_make_float3(mat[2][0], mat[2][1], mat[2][2]));
}

#endif // SIMD_CONVERT_H_INCLUDED
