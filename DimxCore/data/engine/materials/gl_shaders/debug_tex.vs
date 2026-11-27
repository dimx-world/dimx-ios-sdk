DIMX_FLOAT_PRECISION

// The debug pass's textured quads (RenderLines::drawTexturedQuad): a picture
// on a plane in the scene - the editor's keyframe pictures on their frusta.
in vec3 vPosition;
in vec2 vTexCoord;

uniform mat4 vMVPMat;

out vec2 fTexCoord;

void main()
{
    fTexCoord = vTexCoord;
    gl_Position = vMVPMat * vec4(vPosition, 1);
}
