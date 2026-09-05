DIMX_FLOAT_PRECISION

// Signed-distance-field text. The atlas stores a distance value per texel (R channel); the edge
// is at 0.5. Using the screen-space derivative (fwidth) for the smoothstep width keeps glyph edges
// crisp at any scale / viewing distance, so a single baked size suffices.

#ifdef VA_vTexCoord
in vec2 fTexCoord;
#endif

out vec4 outColor;

uniform vec4 fBaseColor;
uniform vec4 fAddColor;
uniform vec4 fMultColor;
#ifdef VA_vTexCoord
uniform sampler2D fBaseColorMap; // SDF atlas
#endif

void main()
{
    vec4 baseColor = fBaseColor;

#ifdef VA_vTexCoord
    float dist = texture(fBaseColorMap, fTexCoord).r;
    float w = fwidth(dist);
    float alpha = smoothstep(0.5 - w, 0.5 + w, dist);
    if (alpha <= 0.0) {
        discard;
    }
    baseColor.a *= alpha;
#endif

    // Premultiplied out, like every shader: the blend is ONE / ONE_MINUS_SRC_ALPHA.
    vec4 color = (baseColor + fAddColor) * fMultColor;
    outColor = vec4(color.rgb * color.a, color.a);
}
