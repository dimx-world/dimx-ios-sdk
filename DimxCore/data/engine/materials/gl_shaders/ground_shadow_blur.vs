DIMX_FLOAT_PRECISION

// One triangle over the whole target - (-1,-1), (3,-1), (-1,3) - made from the
// vertex index, so the pass needs no vertex buffer.

out vec2 fTexCoord;

void main()
{
    vec2 pos = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2)) * 2.0 - 1.0;
    fTexCoord = pos * 0.5 + 0.5;
    gl_Position = vec4(pos, 0.0, 1.0);
}
