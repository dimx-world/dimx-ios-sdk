const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.vec2) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Vec2.');
}

const { vec2 } = glMatrix;
const { EPSILON } = glMatrix;
const scratch = vec2.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isVec2Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y);

const readVec = (value) => {
    if (value instanceof Vec2) {
        return value.data;
    }

    if (isArrayLike(value)) {
        return value;
    }

    if (value && value.data && value.data.length === 2) {
        return value.data;
    }

    if (isVec2Object(value)) {
        scratch[0] = value.x;
        scratch[1] = value.y;
        return scratch;
    }

    throw new TypeError('Expected Vec2, array-like, or {x, y}.');
};

export class Vec2 {
    constructor(x = 0, y = 0) {
        this.data = vec2.create();
        this.set(x, y);
    }

    static from(source) {
        return new Vec2(source);
    }

    static isVec2(value) {
        return value instanceof Vec2;
    }

    static zero() {
        return new Vec2(0, 0);
    }

    static unitX() {
        return new Vec2(1, 0);
    }

    static unitY() {
        return new Vec2(0, 1);
    }

    static add(a, b) {
        return Vec2.from(a).add(b);
    }

    static subtract(a, b) {
        return Vec2.from(a).subtract(b);
    }

    static multiply(a, b) {
        return Vec2.from(a).multiply(b);
    }

    static divide(a, b) {
        return Vec2.from(a).divide(b);
    }

    static scale(a, scalar) {
        return Vec2.from(a).scale(scalar);
    }

    static lerp(a, b, t) {
        return Vec2.from(a).lerp(b, t);
    }

    static dot(a, b) {
        return vec2.dot(readVec(a), readVec(b));
    }

    set(x = 0, y = 0) {
        if (x instanceof Vec2) {
            return this.copy(x);
        }

        if (isArrayLike(x)) {
            vec2.copy(this.data, x);
            return this;
        }

        if (x && x.data && x.data.length === 2) {
            vec2.copy(this.data, x.data);
            return this;
        }

        if (isVec2Object(x)) {
            vec2.set(this.data, x.x, x.y);
            return this;
        }

        vec2.set(this.data, x, y);
        return this;
    }

    copy(source) {
        vec2.copy(this.data, readVec(source));
        return this;
    }

    clone() {
        return new Vec2(this.data);
    }

    add(other) {
        vec2.add(this.data, this.data, readVec(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        vec2.subtract(this.data, this.data, readVec(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    multiply(other) {
        vec2.multiply(this.data, this.data, readVec(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    divide(other) {
        vec2.divide(this.data, this.data, readVec(other));
        return this;
    }

    divided(other) {
        return this.clone().divide(other);
    }

    scale(scalar) {
        vec2.scale(this.data, this.data, scalar);
        return this;
    }

    scaled(scalar) {
        return this.clone().scale(scalar);
    }

    scaleAndAdd(other, scalar) {
        vec2.scaleAndAdd(this.data, this.data, readVec(other), scalar);
        return this;
    }

    normalize() {
        vec2.normalize(this.data, this.data);
        return this;
    }

    normalized() {
        return this.clone().normalize();
    }

    negate() {
        vec2.negate(this.data, this.data);
        return this;
    }

    negated() {
        return this.clone().negate();
    }

    inverse() {
        vec2.inverse(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().inverse();
    }

    min(other) {
        vec2.min(this.data, this.data, readVec(other));
        return this;
    }

    max(other) {
        vec2.max(this.data, this.data, readVec(other));
        return this;
    }

    clamp(min, max) {
        vec2.max(this.data, this.data, readVec(min));
        vec2.min(this.data, this.data, readVec(max));
        return this;
    }

    lerp(target, t) {
        vec2.lerp(this.data, this.data, readVec(target), t);
        return this;
    }

    dot(other) {
        return vec2.dot(this.data, readVec(other));
    }

    distance(other) {
        return vec2.distance(this.data, readVec(other));
    }

    distanceSquared(other) {
        return vec2.squaredDistance(this.data, readVec(other));
    }

    length() {
        return vec2.length(this.data);
    }

    lengthSquared() {
        return vec2.squaredLength(this.data);
    }

    equals(other, tolerance = EPSILON) {
        const target = readVec(other);
        const ax = this.data[0];
        const ay = this.data[1];
        const bx = target[0];
        const by = target[1];
        const compare = (a, b) => Math.abs(a - b) <= tolerance * Math.max(1, Math.abs(a), Math.abs(b));
        return compare(ax, bx) && compare(ay, by);
    }

    toArray() {
        return Array.from(this.data);
    }

    toFloat32Array() {
        return new Float32Array(this.data);
    }

    toJSON() {
        return { x: this.x, y: this.y };
    }

    toString() {
        return `Vec2(${this.x}, ${this.y})`;
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
}

export default Vec2;
