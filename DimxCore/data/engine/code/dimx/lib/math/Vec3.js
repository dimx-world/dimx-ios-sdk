const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.vec3) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Vec3.');
}

const { vec3 } = glMatrix;
const { EPSILON } = glMatrix;
const scratch = vec3.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isVec3Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);

const readVec = (value) => {
    if (value instanceof Vec3) {
        return value.data;
    }

    if (isArrayLike(value)) {
        return value;
    }

    if (isVec3Object(value)) {
        scratch[0] = value.x;
        scratch[1] = value.y;
        scratch[2] = value.z;
        return scratch;
    }

    throw new TypeError('Expected Vec3, array-like, or {x, y, z}.');
};

export class Vec3 {
    constructor(x = 0, y = 0, z = 0) {
        this.data = vec3.create();
        this.set(x, y, z);
    }

    static from(source) {
        return new Vec3(source);
    }

    static isVec3(value) {
        return value instanceof Vec3;
    }

    static zero() {
        return new Vec3(0, 0, 0);
    }

    static unitX() {
        return new Vec3(1, 0, 0);
    }

    static unitY() {
        return new Vec3(0, 1, 0);
    }

    static unitZ() {
        return new Vec3(0, 0, 1);
    }

    static add(a, b) {
        return Vec3.from(a).add(b);
    }

    static subtract(a, b) {
        return Vec3.from(a).subtract(b);
    }

    static multiply(a, b) {
        return Vec3.from(a).multiply(b);
    }

    static divide(a, b) {
        return Vec3.from(a).divide(b);
    }

    static scale(a, scalar) {
        return Vec3.from(a).scale(scalar);
    }

    static cross(a, b) {
        return Vec3.from(a).cross(b);
    }

    static lerp(a, b, t) {
        return Vec3.from(a).lerp(b, t);
    }

    set(x = 0, y = 0, z = 0) {
        if (x instanceof Vec3) {
            return this.copy(x);
        }

        if (isArrayLike(x)) {
            vec3.copy(this.data, x);
            return this;
        }

        if (isVec3Object(x)) {
            vec3.set(this.data, x.x, x.y, x.z);
            return this;
        }

        vec3.set(this.data, x, y, z);
        return this;
    }

    copy(source) {
        vec3.copy(this.data, readVec(source));
        return this;
    }

    clone() {
        return new Vec3(this.data);
    }

    add(other) {
        vec3.add(this.data, this.data, readVec(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        vec3.subtract(this.data, this.data, readVec(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    multiply(other) {
        vec3.multiply(this.data, this.data, readVec(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    divide(other) {
        vec3.divide(this.data, this.data, readVec(other));
        return this;
    }

    divided(other) {
        return this.clone().divide(other);
    }

    scale(scalar) {
        vec3.scale(this.data, this.data, scalar);
        return this;
    }

    scaled(scalar) {
        return this.clone().scale(scalar);
    }

    scaleAndAdd(other, scalar) {
        vec3.scaleAndAdd(this.data, this.data, readVec(other), scalar);
        return this;
    }

    normalize() {
        vec3.normalize(this.data, this.data);
        return this;
    }

    normalized() {
        return this.clone().normalize();
    }

    negate() {
        vec3.negate(this.data, this.data);
        return this;
    }

    negated() {
        return this.clone().negate();
    }

    inverse() {
        vec3.inverse(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().inverse();
    }

    min(other) {
        vec3.min(this.data, this.data, readVec(other));
        return this;
    }

    max(other) {
        vec3.max(this.data, this.data, readVec(other));
        return this;
    }

    clamp(min, max) {
        vec3.max(this.data, this.data, readVec(min));
        vec3.min(this.data, this.data, readVec(max));
        return this;
    }

    lerp(target, t) {
        vec3.lerp(this.data, this.data, readVec(target), t);
        return this;
    }

    crossed(other) {
        return this.clone().cross(other);
    }

    cross(other) {
        vec3.cross(this.data, this.data, readVec(other));
        return this;
    }

    dot(other) {
        return vec3.dot(this.data, readVec(other));
    }

    distance(other) {
        return vec3.distance(this.data, readVec(other));
    }

    distanceSquared(other) {
        return vec3.squaredDistance(this.data, readVec(other));
    }

    length() {
        return vec3.length(this.data);
    }

    lengthSquared() {
        return vec3.squaredLength(this.data);
    }

    equals(other, tolerance = EPSILON) {
        const target = readVec(other);
        const ax = this.data[0];
        const ay = this.data[1];
        const az = this.data[2];
        const bx = target[0];
        const by = target[1];
        const bz = target[2];

        return (
            Math.abs(ax - bx) <= tolerance * Math.max(1, Math.abs(ax), Math.abs(bx)) &&
            Math.abs(ay - by) <= tolerance * Math.max(1, Math.abs(ay), Math.abs(by)) &&
            Math.abs(az - bz) <= tolerance * Math.max(1, Math.abs(az), Math.abs(bz))
        );
    }

    toArray() {
        return Array.from(this.data);
    }

    toFloat32Array() {
        return new Float32Array(this.data);
    }

    toJSON() {
        return { x: this.x, y: this.y, z: this.z };
    }

    toString() {
        return `Vec3(${this.x}, ${this.y}, ${this.z})`;
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
}

export default Vec3;
