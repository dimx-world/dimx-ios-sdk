DIMX_FLOAT_PRECISION

in vec2 fTexCoord;

uniform sampler2D fTexture;
// The quad's opacity (RenderLines::drawTexturedQuad's alpha).
uniform float fAlpha;
// 1 when the texture's colour is multiplied by its alpha already (DebugQuad::premultiplied):
// an SVG tile. A straight-alpha picture is multiplied here.
uniform float fPremultiplied;

out vec4 outColor;

void main()
{
    vec4 color = texture(fTexture, fTexCoord);
    // Premultiplied out, like every shader: the blend is ONE / ONE_MINUS_SRC_ALPHA.
    float alpha = color.a * fAlpha;
    outColor = vec4(color.rgb * (fPremultiplied > 0.5 ? fAlpha : alpha), alpha);
}
