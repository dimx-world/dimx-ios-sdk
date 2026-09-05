DIMX_FLOAT_PRECISION

in vec4 fColor;
out vec4 outColor;

void main()
{
    // Premultiplied out, like every shader: the blend is ONE / ONE_MINUS_SRC_ALPHA.
    outColor = vec4(fColor.rgb * fColor.a, fColor.a);
}
