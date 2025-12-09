const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.vec4) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Vec4.');
}

const { vec4 } = glMatrix;
const { EPSILON } = glMatrix;
const scratch = vec4.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isVec4Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z) && Number.isFinite(value.w);

const readVec = (value) => {
    if (value instanceof Vec4) {
        return value.data;
    }

    if (isArrayLike(value)) {
        return value;
    }

    if (value && value.data && value.data.length === 4) {
        return value.data;
    }

    if (isVec4Object(value)) {
        scratch[0] = value.x;
        scratch[1] = value.y;
        scratch[2] = value.z;
        scratch[3] = value.w;
        return scratch;
    }

    throw new TypeError('Expected Vec4, array-like, or {x, y, z, w}.');
};

export class Vec4 {
    constructor(x = 0, y = 0, z = 0, w = 0) {
        this.data = vec4.create();
        this.set(x, y, z, w);
    }

    static from(source) {
        return new Vec4(source);
    }

    static isVec4(value) {
        return value instanceof Vec4;
    }

    static zero() {
        return new Vec4(0, 0, 0, 0);
    }

    static unitX() {
        return new Vec4(1, 0, 0, 0);
    }

    static unitY() {
        return new Vec4(0, 1, 0, 0);
    }

    static unitZ() {
        return new Vec4(0, 0, 1, 0);
    }

    static unitW() {
        return new Vec4(0, 0, 0, 1);
    }

    static add(a, b) {
        return Vec4.from(a).add(b);
    }

    static subtract(a, b) {
        return Vec4.from(a).subtract(b);
    }

    static multiply(a, b) {
        return Vec4.from(a).multiply(b);
    }

    static divide(a, b) {
        return Vec4.from(a).divide(b);
    }

    static scale(a, scalar) {
        return Vec4.from(a).scale(scalar);
    }

    static lerp(a, b, t) {
        return Vec4.from(a).lerp(b, t);
    }

    static dot(a, b) {
        return vec4.dot(readVec(a), readVec(b));
    }

    set(x = 0, y = 0, z = 0, w = 0) {
        if (x instanceof Vec4) {
            return this.copy(x);
        }

        if (isArrayLike(x)) {
            vec4.copy(this.data, x);
            return this;
        }

        if (x && x.data && x.data.length === 4) {
            vec4.copy(this.data, x.data);
            return this;
        }

        if (isVec4Object(x)) {
            vec4.set(this.data, x.x, x.y, x.z, x.w);
            return this;
        }

        vec4.set(this.data, x, y, z, w);
        return this;
    }

    copy(source) {
        vec4.copy(this.data, readVec(source));
        return this;
    }

    clone() {
        return new Vec4(this.data);
    }

    add(other) {
        vec4.add(this.data, this.data, readVec(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        vec4.subtract(this.data, this.data, readVec(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    multiply(other) {
        vec4.multiply(this.data, this.data, readVec(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    divide(other) {
        vec4.divide(this.data, this.data, readVec(other));
        return this;
    }

    divided(other) {
        return this.clone().divide(other);
    }

    scale(scalar) {
        vec4.scale(this.data, this.data, scalar);
        return this;
    }

    scaled(scalar) {
        return this.clone().scale(scalar);
    }

    scaleAndAdd(other, scalar) {
        vec4.scaleAndAdd(this.data, this.data, readVec(other), scalar);
        return this;
    }

    normalize() {
        vec4.normalize(this.data, this.data);
        return this;
    }

    normalized() {
        return this.clone().normalize();
    }

    negate() {
        vec4.negate(this.data, this.data);
        return this;
    }

    negated() {
        return this.clone().negate();
    }

    inverse() {
        vec4.inverse(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().inverse();
    }

    min(other) {
        vec4.min(this.data, this.data, readVec(other));
        return this;
    }

    max(other) {
        vec4.max(this.data, this.data, readVec(other));
        return this;
    }

    clamp(min, max) {
        vec4.max(this.data, this.data, readVec(min));
        vec4.min(this.data, this.data, readVec(max));
        return this;
    }

    lerp(target, t) {
        vec4.lerp(this.data, this.data, readVec(target), t);
        return this;
    }

    dot(other) {
        return vec4.dot(this.data, readVec(other));
    }

    distance(other) {
        return vec4.distance(this.data, readVec(other));
    }

    distanceSquared(other) {
        return vec4.squaredDistance(this.data, readVec(other));
    }

    length() {
        return vec4.length(this.data);
    }

    lengthSquared() {
        return vec4.squaredLength(this.data);
    }

    equals(other, tolerance = EPSILON) {
        const target = readVec(other);
        const ax = this.data[0];
        const ay = this.data[1];
        const az = this.data[2];
        const aw = this.data[3];
        const bx = target[0];
        const by = target[1];
        const bz = target[2];
        const bw = target[3];

        const compare = (a, b) => Math.abs(a - b) <= tolerance * Math.max(1, Math.abs(a), Math.abs(b));
        return compare(ax, bx) && compare(ay, by) && compare(az, bz) && compare(aw, bw);
    }

    toArray() {
        return Array.from(this.data);
    }

    toFloat32Array() {
        return new Float32Array(this.data);
    }

    toJSON() {
        return { x: this.x, y: this.y, z: this.z, w: this.w };
    }

    toString() {
        return `Vec4(${this.x}, ${this.y}, ${this.z}, ${this.w})`;
    }

    valueOf() {
        return this.data;
    }

    [Symbol.iterator]() {
        return this.data[Symbol.iterator]();
    }

    get x() {
        return this.data[0];
    }

    set x(value) {
        this.data[0] = value;
    }

    get y() {
        return this.data[1];
    }

    set y(value) {
        this.data[1] = value;
    }

    get z() {
        return this.data[2];
    }

    set z(value) {
        this.data[2] = value;
    }

    get w() {
        return this.data[3];
    }

    set w(value) {
        this.data[3] = value;
    }
}

export default Vec4;
