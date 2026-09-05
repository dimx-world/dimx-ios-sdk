DIMX_FLOAT_PRECISION

in vec2 fTexCoord;
in vec4 fColor;

uniform sampler2D fTexture;
uniform float fRedChannel;
// Whether the texture's colour is already multiplied by its alpha: images
// the engine decodes and its render targets are, the font atlas and video
// frames are not.
uniform bool fPremultiplied;

out vec4 outColor;

void main()
{
    vec4 texCol = texture(fTexture, fTexCoord.st);
    if (fRedChannel > 0.5) {
        texCol = vec4(1.0, 1.0, 1.0, texCol.r);
    }
    if (!fPremultiplied) {
        texCol.rgb *= texCol.a;
    }
    // Premultiplied out, like every shader: the pass blends ONE / ONE_MINUS_SRC_ALPHA.
    // This is also what makes a UI render target hold premultiplied colour. The
    // vertex colour is a straight tint with an alpha, applied as one.
    outColor = vec4(fColor.rgb * fColor.a * texCol.rgb, fColor.a * texCol.a);
}
