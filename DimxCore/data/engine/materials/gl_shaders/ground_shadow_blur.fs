DIMX_FLOAT_PRECISION

// One axis of the ground shadow's blur (GroundShadow). The first pass reads the
// casters' depth - their height above the ground over the fade height, 1 where
// nothing casts - and makes it darkness, 1 - depth; the second blurs the
// first's darkness along the other axis. Nine taps of a Gaussian, fStep apart.

in vec2 fTexCoord;

uniform sampler2D fSource;
uniform vec2 fStep;
uniform bool fFromDepth;

out vec4 outColor;

float darkness(vec2 uv)
{
    float value = texture(fSource, uv).r;
    return fFromDepth ? 1.0 - value : value;
}

void main()
{
    // exp(-k * k / 8) for k = 0..4: a sigma of two taps.
    const float w0 = 1.0;
    const float w1 = 0.8824969;
    const float w2 = 0.6065307;
    const float w3 = 0.3246525;
    const float w4 = 0.1353353;
    const float total = w0 + 2.0 * (w1 + w2 + w3 + w4);

    float sum = w0 * darkness(fTexCoord);
    sum += w1 * (darkness(fTexCoord + fStep) + darkness(fTexCoord - fStep));
    sum += w2 * (darkness(fTexCoord + 2.0 * fStep) + darkness(fTexCoord - 2.0 * fStep));
    sum += w3 * (darkness(fTexCoord + 3.0 * fStep) + darkness(fTexCoord - 3.0 * fStep));
    sum += w4 * (darkness(fTexCoord + 4.0 * fStep) + darkness(fTexCoord - 4.0 * fStep));

    outColor = vec4(sum / total, 0.0, 0.0, 1.0);
}
