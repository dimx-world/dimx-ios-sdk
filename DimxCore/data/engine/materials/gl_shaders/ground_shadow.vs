DIMX_FLOAT_PRECISION

// The ground shadow's quad (GroundShadow): the square (u, 0, v), u and v from 0
// to 1, onto the ground region by vQuadMat - made from the vertex index as a
// strip, (0,0) (0,1) (1,0) (1,1), counter-clockwise seen from above.

uniform mat4 vViewMat;
uniform mat4 vViewProjMat;
uniform mat4 vQuadMat;

out vec2 fTexCoord;
out vec4 fPosition;
out vec4 fViewPosition;

void main()
{
    vec2 uv = vec2(float(gl_VertexID >> 1), float(gl_VertexID & 1));
    vec4 worldPos = vQuadMat * vec4(uv.x, 0.0, uv.y, 1.0);
    gl_Position = vViewProjMat * worldPos;
    // A hair towards the camera, so that an occluder standing for the real
    // floor at the same height does not hide it.
    gl_Position.z -= (1.0 / 8192.0) * abs(gl_Position.w);

    fTexCoord = uv;
    fPosition = gl_Position;
    fViewPosition = vViewMat * worldPos;
}
