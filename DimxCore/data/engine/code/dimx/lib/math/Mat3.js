const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.mat3 || !glMatrix.vec2) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Mat3.');
}

const { mat3, vec2 } = glMatrix;
const { EPSILON } = glMatrix;
const scratchVecA = vec2.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isVec2Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y);

export class Mat3 {
    constructor(...args) {
        this.data = mat3.create();
        if (args.length === 1 && args[0] !== undefined) {
            this.set(args[0]);
        } else if (args.length === 9) {
            this.set(...args);
        } else if (args.length !== 0) {
            throw new TypeError('Expected no arguments, a Mat3-like value, or 9 numeric values.');
        }
    }

    static from(source) {
        return new Mat3(source);
    }

    static identity() {
        return new Mat3();
    }

    static multiply(a, b) {
        return Mat3.from(a).multiply(b);
    }

    static add(a, b) {
        return Mat3.from(a).add(b);
    }

    static subtract(a, b) {
        return Mat3.from(a).subtract(b);
    }

    static fromTranslation(translation) {
        return new Mat3().fromTranslation(translation);
    }

    static fromScaling(scale) {
        return new Mat3().fromScaling(scale);
    }

    static fromRotation(radians) {
        return new Mat3().fromRotation(radians);
    }

    static fromMat4(source) {
        return new Mat3().fromMat4(source);
    }

    set(...args) {
        if (args.length === 0) {
            return this;
        }

        if (args.length === 1) {
            const [value] = args;
            const input = readMat(value);
            if (input !== this.data) {
                mat3.copy(this.data, input);
            }
            return this;
        }

        if (args.length === 9) {
            mat3.set(this.data, ...args);
            return this;
        }

        throw new TypeError('Expected Mat3 input or 9 numeric values.');
    }

    copy(source) {
        mat3.copy(this.data, readMat(source));
        return this;
    }

    clone() {
        return new Mat3(this.data);
    }

    identity() {
        mat3.identity(this.data);
        return this;
    }

    transpose() {
        mat3.transpose(this.data, this.data);
        return this;
    }

    transposed() {
        return this.clone().transpose();
    }

    invert() {
        mat3.invert(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().invert();
    }

    adjoint() {
        mat3.adjoint(this.data, this.data);
        return this;
    }

    determinant() {
        return mat3.determinant(this.data);
    }

    frob() {
        return mat3.frob(this.data);
    }

    multiply(other) {
        mat3.multiply(this.data, this.data, readMat(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    premultiply(other) {
        mat3.multiply(this.data, readMat(other), this.data);
        return this;
    }

    premultiplied(other) {
        return this.clone().premultiply(other);
    }

    add(other) {
        mat3.add(this.data, this.data, readMat(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        mat3.subtract(this.data, this.data, readMat(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    multiplyScalar(scalar) {
        mat3.multiplyScalar(this.data, this.data, scalar);
        return this;
    }

    multipliedScalar(scalar) {
        return this.clone().multiplyScalar(scalar);
    }

    translate(offset) {
        mat3.translate(this.data, this.data, readVec2(offset, scratchVecA));
        return this;
    }

    translated(offset) {
        return this.clone().translate(offset);
    }

    fromTranslation(translation) {
        mat3.fromTranslation(this.data, readVec2(translation, scratchVecA));
        return this;
    }

    scale(scale) {
        const vector = typeof scale === 'number' ? setVec2Uniform(scratchVecA, scale) : readVec2(scale, scratchVecA);
        mat3.scale(this.data, this.data, vector);
        return this;
    }

    scaled(scale) {
        return this.clone().scale(scale);
    }

    fromScaling(scale) {
        const vector = typeof scale === 'number' ? setVec2Uniform(scratchVecA, scale) : readVec2(scale, scratchVecA);
        mat3.fromScaling(this.data, vector);
        return this;
    }

    rotate(radians) {
        mat3.rotate(this.data, this.data, radians);
        return this;
    }

    rotated(radians) {
        return this.clone().rotate(radians);
    }

    fromRotation(radians) {
        mat3.fromRotation(this.data, radians);
        return this;
    }

    fromMat4(source) {
        const input = isArrayLike(source) ? source : (source && source.data);
        if (!isArrayLike(input) || input.length < 16) {
            throw new TypeError('Expected Mat4, array-like of length 16, or { data: length 16 }');
        }
        mat3.fromMat4(this.data, input);
        return this;
    }

    // Applies this matrix to a 2D point as (M * vec3(point, 1)).xy.
    transformPoint(point) {
        const value = readVec2(point, scratchVecA);
        const x = value[0];
        const y = value[1];
        return [
            this.data[0] * x + this.data[3] * y + this.data[6],
            this.data[1] * x + this.data[4] * y + this.data[7]
        ];
    }

    equals(other, tolerance = EPSILON) {
        const target = readMat(other);
        for (let i = 0; i < 9; i++) {
            const a = this.data[i];
            const b = target[i];
            if (Math.abs(a - b) > tolerance * Math.max(1, Math.abs(a), Math.abs(b))) {
                return false;
            }
        }
        return true;
    }

    toArray() {
        return Array.from(this.data);
    }

    toFloat32Array() {
        return new Float32Array(this.data);
    }

    toJSON() {
        return { data: this.toArray() };
    }

    toString() {
        return `Mat3(${this.toArray().join(', ')})`;
    }

    valueOf() {
        return this.data;
    }

    [Symbol.iterator]() {
        return this.data[Symbol.iterator]();
    }
}

export default Mat3;

function readMat(value) {
    if (!value) {
        throw new TypeError('Expected Mat3-like input.');
    }

    if (isArrayLike(value)) {
        if (value.length < 9) {
            throw new TypeError('Expected array-like Mat3 input with at least 9 elements.');
        }
        return value;
    }

    if ('data' in value && isArrayLike(value.data) && value.data.length >= 9) {
        return value.data;
    }

    throw new TypeError('Expected Mat3, array-like of length 9, or { data: length 9 }');
}

function readVec2(value, target) {
    if (value && value.data && value.data.length === 2) {
        target[0] = value.data[0];
        target[1] = value.data[1];
        return target;
    }

    if (isArrayLike(value)) {
        if (value.length < 2) {
            throw new TypeError('Expected array-like Vec2 input with at least 2 elements.');
        }
        target[0] = value[0];
        target[1] = value[1];
        return target;
    }

    if (isVec2Object(value)) {
        target[0] = value.x;
        target[1] = value.y;
        return target;
    }

    throw new TypeError('Expected Vec2-like input.');
}

function setVec2Uniform(target, value) {
    target[0] = value;
    target[1] = value;
    return target;
}
