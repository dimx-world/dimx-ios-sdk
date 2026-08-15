import { Vec2 } from './Vec2.js';
import { Mat3 } from './Mat3.js';

// Vec2 already accepts Vec2 instances, array-likes and {x, y}; this adds the two
// forms it cannot express: a bare number meaning "same on both axes", and a
// missing value falling back to `fallback`. Anything Vec2 cannot interpret comes
// back as NaN, which we turn into a clear error rather than a silent bad matrix.
function toVec2(value, fallback) {
    if (value === undefined || value === null) {
        return new Vec2(fallback, fallback);
    }

    if (typeof value === 'number') {
        return new Vec2(value, value);
    }

    const result = new Vec2(value);
    if (!Number.isFinite(result.x) || !Number.isFinite(result.y)) {
        throw new TypeError('Expected a number, Vec2, array-like, or {x, y}.');
    }
    return result;
}

export class MathUtils {
    /**
     * Builds an affine texture-coordinate transform as a Mat3.
     *
     * Shaders apply it as uv' = (M * vec3(uv, 1)).xy, so the offset occupies the
     * third column. Assign the result to a material's `uvTransform`:
     *
     *   entity.materials.get('Default').uvTransform =
     *       MathUtils.uvTransform(new Vec2(0.25, 0.5), new Vec2(0.75, 0.25));
     *
     * That maps the mesh's 0..1 UVs onto the image sub-rect
     * [0.75 .. 1.0] x [0.25 .. 0.75].
     *
     * @param {number|Vec2|number[]|{x,y}} scale  defaults to 1 on both axes
     * @param {number|Vec2|number[]|{x,y}} offset defaults to 0 on both axes
     * @returns {Mat3}
     */
    static uvTransform(scale, offset) {
        const scaleVec = toVec2(scale, 1);
        const offsetVec = toVec2(offset, 0);

        const result = new Mat3();
        result.data[0] = scaleVec.x;
        result.data[4] = scaleVec.y;
        result.data[6] = offsetVec.x;
        result.data[7] = offsetVec.y;
        return result;
    }
}

export default MathUtils;
