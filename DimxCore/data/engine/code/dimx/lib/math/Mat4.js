const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.mat4 || !glMatrix.vec3) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Mat4.');
}

const { mat4, vec3 } = glMatrix;
const { EPSILON } = glMatrix;
const scratchVecA = vec3.create();
const scratchVecB = vec3.create();
const scratchVecC = vec3.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isVec3Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);

export class Mat4 {
    constructor(...args) {
        this.data = mat4.create();
        if (args.length === 1 && args[0] !== undefined) {
            this.set(args[0]);
        } else if (args.length === 16) {
            this.set(...args);
        } else if (args.length !== 0) {
            throw new TypeError('Expected no arguments, a Mat4-like value, or 16 numeric values.');
        }
    }

    static from(source) {
        return new Mat4(source);
    }

    static identity() {
        return new Mat4();
    }

    static multiply(a, b) {
        return Mat4.from(a).multiply(b);
    }

    static add(a, b) {
        return Mat4.from(a).add(b);
    }

    static subtract(a, b) {
        return Mat4.from(a).subtract(b);
    }

    static lerp(a, b, t) {
        return Mat4.from(a).lerp(b, t);
    }

    static fromTranslation(translation) {
        return new Mat4().fromTranslation(translation);
    }

    static fromScaling(scale) {
        return new Mat4().fromScaling(scale);
    }

    static fromRotation(radians, axis) {
        return new Mat4().fromRotation(radians, axis);
    }

    static lookAt(eye, center, up) {
        return new Mat4().lookAt(eye, center, up);
    }

    static targetTo(eye, target, up) {
        return new Mat4().targetTo(eye, target, up);
    }

    static perspective(fovy, aspect, near, far) {
        return new Mat4().perspective(fovy, aspect, near, far);
    }

    static ortho(left, right, bottom, top, near, far) {
        return new Mat4().ortho(left, right, bottom, top, near, far);
    }

    set(...args) {
        if (args.length === 0) {
            return this;
        }

        if (args.length === 1) {
            const [value] = args;
            const input = readMat(value);
            if (input !== this.data) {
                mat4.copy(this.data, input);
            }
            return this;
        }

        if (args.length === 16) {
            mat4.set(this.data, ...args);
            return this;
        }

        throw new TypeError('Expected Mat4 input or 16 numeric values.');
    }

    copy(source) {
        mat4.copy(this.data, readMat(source));
        return this;
    }

    clone() {
        return new Mat4(this.data);
    }

    identity() {
        mat4.identity(this.data);
        return this;
    }

    transpose() {
        mat4.transpose(this.data, this.data);
        return this;
    }

    invert() {
        mat4.invert(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().invert();
    }

    adjoint() {
        mat4.adjoint(this.data, this.data);
        return this;
    }

    determinant() {
        return mat4.determinant(this.data);
    }

    frob() {
        return mat4.frob(this.data);
    }

    multiply(other) {
        mat4.multiply(this.data, this.data, readMat(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    premultiply(other) {
        mat4.multiply(this.data, readMat(other), this.data);
        return this;
    }

    premultiplied(other) {
        return this.clone().premultiply(other);
    }

    add(other) {
        mat4.add(this.data, this.data, readMat(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        mat4.subtract(this.data, this.data, readMat(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    multiplyScalar(scalar) {
        mat4.multiplyScalar(this.data, this.data, scalar);
        return this;
    }

    multipliedScalar(scalar) {
        return this.clone().multiplyScalar(scalar);
    }

    lerp(target, t) {
        mat4.lerp(this.data, this.data, readMat(target), t);
        return this;
    }

    lerped(target, t) {
        return this.clone().lerp(target, t);
    }

    translate(offset) {
        mat4.translate(this.data, this.data, readVec3(offset, scratchVecA));
        return this;
    }

    translated(offset) {
        return this.clone().translate(offset);
    }

    fromTranslation(translation) {
        mat4.fromTranslation(this.data, readVec3(translation, scratchVecA));
        return this;
    }

    scale(scale) {
        const vector = typeof scale === 'number' ? setVec3Uniform(scratchVecA, scale) : readVec3(scale, scratchVecA);
        mat4.scale(this.data, this.data, vector);
        return this;
    }

    scaled(scale) {
        return this.clone().scale(scale);
    }

    fromScaling(scale) {
        const vector = typeof scale === 'number' ? setVec3Uniform(scratchVecA, scale) : readVec3(scale, scratchVecA);
        mat4.fromScaling(this.data, vector);
        return this;
    }

    rotate(radians, axis) {
        mat4.rotate(this.data, this.data, radians, readVec3(axis, scratchVecA));
        return this;
    }

    rotated(radians, axis) {
        return this.clone().rotate(radians, axis);
    }

    rotateX(radians) {
        mat4.rotateX(this.data, this.data, radians);
        return this;
    }

    rotatedX(radians) {
        return this.clone().rotateX(radians);
    }

    rotateY(radians) {
        mat4.rotateY(this.data, this.data, radians);
        return this;
    }

    rotatedY(radians) {
        return this.clone().rotateY(radians);
    }

    rotateZ(radians) {
        mat4.rotateZ(this.data, this.data, radians);
        return this;
    }

    rotatedZ(radians) {
        return this.clone().rotateZ(radians);
    }

    fromRotation(radians, axis) {
        mat4.fromRotation(this.data, radians, readVec3(axis, scratchVecA));
        return this;
    }

    lookAt(eye, center, up) {
        mat4.lookAt(
            this.data,
            readVec3(eye, scratchVecA),
            readVec3(center, scratchVecB),
            readVec3(up, scratchVecC)
        );
        return this;
    }

    targetTo(eye, target, up) {
        mat4.targetTo(
            this.data,
            readVec3(eye, scratchVecA),
            readVec3(target, scratchVecB),
            readVec3(up, scratchVecC)
        );
        return this;
    }

    perspective(fovy, aspect, near, far) {
        mat4.perspective(this.data, fovy, aspect, near, far);
        return this;
    }

    ortho(left, right, bottom, top, near, far) {
        mat4.ortho(this.data, left, right, bottom, top, near, far);
        return this;
    }

    getTranslation(out = null) {
        const result = out ? readVec3(out, scratchVecA) : scratchVecA;
        mat4.getTranslation(result, this.data);
        if (out) {
            writeVec3(out, result);
            return out;
        }
        return [result[0], result[1], result[2]];
    }

    setTranslation(translation) {
        const value = readVec3(translation, scratchVecA);
        this.data[12] = value[0];
        this.data[13] = value[1];
        this.data[14] = value[2];
        return this;
    }

    getScaling(out = null) {
        const result = out ? readVec3(out, scratchVecA) : scratchVecA;
        mat4.getScaling(result, this.data);
        if (out) {
            writeVec3(out, result);
            return out;
        }
        return [result[0], result[1], result[2]];
    }

    equals(other, tolerance = EPSILON) {
        const target = readMat(other);
        for (let i = 0; i < 16; i++) {
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

    valueOf() {
        return this.data;
    }

    [Symbol.iterator]() {
        return this.data[Symbol.iterator]();
    }
}

export default Mat4;

function readMat(value) {
    if (!value) {
        throw new TypeError('Expected Mat4-like input.');
    }

    if (isArrayLike(value)) {
        if (value.length < 16) {
            throw new TypeError('Expected array-like Mat4 input with at least 16 elements.');
        }
        return value;
    }

    if ('data' in value && isArrayLike(value.data) && value.data.length >= 16) {
        return value.data;
    }

    throw new TypeError('Expected Mat4, array-like of length 16, or { data: length 16 }');
}

function readVec3(value, target) {
    if (value && value.data && value.data.length === 3) {
        target[0] = value.data[0];
        target[1] = value.data[1];
        target[2] = value.data[2];
        return target;
    }

    if (isArrayLike(value)) {
        if (value.length < 3) {
            throw new TypeError('Expected array-like Vec3 input with at least 3 elements.');
        }
        target[0] = value[0];
        target[1] = value[1];
        target[2] = value[2];
        return target;
    }

    if (isVec3Object(value)) {
        target[0] = value.x;
        target[1] = value.y;
        target[2] = value.z;
        return target;
    }

    throw new TypeError('Expected Vec3-like input.');
}

function writeVec3(target, source) {
    if (target && target.data && target.data.length === 3) {
        target.data[0] = source[0];
        target.data[1] = source[1];
        target.data[2] = source[2];
        return target;
    }

    if (isArrayLike(target)) {
        target[0] = source[0];
        target[1] = source[1];
        target[2] = source[2];
        return target;
    }

    if (isVec3Object(target)) {
        target.x = source[0];
        target.y = source[1];
        target.z = source[2];
        return target;
    }

    throw new TypeError('Expected Vec3-like output container.');
}

function setVec3Uniform(target, value) {
    target[0] = value;
    target[1] = value;
    target[2] = value;
    return target;
}
