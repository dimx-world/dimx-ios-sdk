DIMX_FLOAT_PRECISION

in vec3 vPosition;
in vec4 vColor;

uniform mat4 vMVPMat;
// The size a dot is drawn at (RenderLines::dotSize), in pixels; lines and triangles ignore it.
uniform float vPointSize;
// What every vertex's alpha is multiplied by: the held surface's and clouds' opacity, 1 for the lists.
uniform float vOpacity;

out vec4 fColor;

void main()
{
    fColor = vec4(vColor.rgb, vColor.a * vOpacity);
    gl_Position = vMVPMat * vec4(vPosition, 1);
    gl_PointSize = vPointSize;
}
