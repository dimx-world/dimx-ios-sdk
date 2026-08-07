const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.quat || !glMatrix.vec3) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Quat.');
}

const { quat, vec3 } = glMatrix;
const { EPSILON } = glMatrix;
const scratch = quat.create();
const axisScratchA = vec3.create();
const axisScratchB = vec3.create();
const axisScratchC = vec3.create();

const isArrayLike = (value) => Array.isArray(value) || ArrayBuffer.isView(value);
const isQuatObject = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z) && Number.isFinite(value.w);
const isVec3Object = (value) => value && typeof value === 'object' && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);

const readQuat = (value) => {
    if (value instanceof Quat) {
        return value.data;
    }

    if (isArrayLike(value)) {
        return value;
    }

    if (value && value.data && value.data.length === 4) {
        return value.data;
    }

    if (isQuatObject(value)) {
        scratch[0] = value.x;
        scratch[1] = value.y;
        scratch[2] = value.z;
        scratch[3] = value.w;
        return scratch;
    }

    throw new TypeError('Expected Quat, array-like, or {x, y, z, w}.');
};

const readVec3 = (value, target) => {
    if (value && value.data && value.data.length === 3) {
        target[0] = value.data[0];
        target[1] = value.data[1];
        target[2] = value.data[2];
        return target;
    }

    if (isArrayLike(value)) {
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
};

const writeVec3 = (target, source) => {
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
};

export class Quat {
    constructor(x = 0, y = 0, z = 0, w = 1) {
        this.data = quat.create();
        this.set(x, y, z, w);
    }

    static from(source) {
        return new Quat(source);
    }

    static isQuat(value) {
        return value instanceof Quat;
    }

    static identity() {
        return new Quat(0, 0, 0, 1);
    }

    static fromAxisAngle(axis, radians) {
        return new Quat().setAxisAngle(axis, radians);
    }

    static fromEuler(x, y, z, order = 'zyx') {
        return new Quat().fromEuler(x, y, z, order);
    }

    static multiply(a, b) {
        return Quat.from(a).multiply(b);
    }

    static slerp(a, b, t) {
        return Quat.from(a).slerp(b, t);
    }

    static dot(a, b) {
        return quat.dot(readQuat(a), readQuat(b));
    }

    set(x = 0, y = 0, z = 0, w = 1) {
        if (x instanceof Quat) {
            return this.copy(x);
        }

        if (isArrayLike(x)) {
            quat.copy(this.data, x);
            return this;
        }

        if (x && x.data && x.data.length === 4) {
            quat.copy(this.data, x.data);
            return this;
        }

        if (isQuatObject(x)) {
            quat.set(this.data, x.x, x.y, x.z, x.w);
            return this;
        }

        quat.set(this.data, x, y, z, w);
        return this;
    }

    copy(source) {
        quat.copy(this.data, readQuat(source));
        return this;
    }

    clone() {
        return new Quat(this.data);
    }

    identity() {
        quat.identity(this.data);
        return this;
    }

    invert() {
        quat.invert(this.data, this.data);
        return this;
    }

    inverted() {
        return this.clone().invert();
    }

    conjugate() {
        quat.conjugate(this.data, this.data);
        return this;
    }

    conjugated() {
        return this.clone().conjugate();
    }

    normalize() {
        quat.normalize(this.data, this.data);
        return this;
    }

    normalized() {
        return this.clone().normalize();
    }

    add(other) {
        quat.add(this.data, this.data, readQuat(other));
        return this;
    }

    added(other) {
        return this.clone().add(other);
    }

    subtract(other) {
        quat.subtract(this.data, this.data, readQuat(other));
        return this;
    }

    subtracted(other) {
        return this.clone().subtract(other);
    }

    scale(scalar) {
        quat.scale(this.data, this.data, scalar);
        return this;
    }

    scaled(scalar) {
        return this.clone().scale(scalar);
    }

    multiply(other) {
        quat.multiply(this.data, this.data, readQuat(other));
        return this;
    }

    multiplied(other) {
        return this.clone().multiply(other);
    }

    premultiply(other) {
        quat.multiply(this.data, readQuat(other), this.data);
        return this;
    }

    premultiplied(other) {
        return this.clone().premultiply(other);
    }

    lerp(target, t) {
        quat.lerp(this.data, this.data, readQuat(target), t);
        return this;
    }

    lerped(target, t) {
        return this.clone().lerp(target, t);
    }

    nlerp(target, t) {
        quat.lerp(this.data, this.data, readQuat(target), t);
        quat.normalize(this.data, this.data);
        return this;
    }

    nlerped(target, t) {
        return this.clone().nlerp(target, t);
    }

    slerp(target, t) {
        quat.slerp(this.data, this.data, readQuat(target), t);
        return this;
    }

    slerped(target, t) {
        return this.clone().slerp(target, t);
    }

    dot(other) {
        return quat.dot(this.data, readQuat(other));
    }

    length() {
        return quat.length(this.data);
    }

    lengthSquared() {
        return quat.squaredLength(this.data);
    }

    setAxisAngle(axis, radians) {
        quat.setAxisAngle(this.data, readVec3(axis, axisScratchA), radians);
        return this;
    }

    fromAxisAngle(axis, radians) {
        return this.setAxisAngle(axis, radians);
    }

    getAxisAngle(outAxis = null) {
        const angle = quat.getAxisAngle(axisScratchA, this.data);
        if (outAxis) {
            writeVec3(outAxis, axisScratchA);
            return angle;
        }
        return { axis: [axisScratchA[0], axisScratchA[1], axisScratchA[2]], angle };
    }

    setAxes(view, right, up) {
        quat.setAxes(
            this.data,
            readVec3(view, axisScratchA),
            readVec3(right, axisScratchB),
            readVec3(up, axisScratchC)
        );
        return this;
    }

    rotateX(radians) {
        quat.rotateX(this.data, this.data, radians);
        return this;
    }

    rotatedX(radians) {
        return this.clone().rotateX(radians);
    }

    rotateY(radians) {
        quat.rotateY(this.data, this.data, radians);
        return this;
    }

    rotatedY(radians) {
        return this.clone().rotateY(radians);
    }

    rotateZ(radians) {
        quat.rotateZ(this.data, this.data, radians);
        return this;
    }

    rotatedZ(radians) {
        return this.clone().rotateZ(radians);
    }

    fromEuler(x, y, z, order = 'zyx') {
        quat.fromEuler(this.data, x, y, z, order);
        return this;
    }

    equals(other, tolerance = EPSILON) {
        const target = readQuat(other);
        const ax = this.data[0];
        const ay = this.data[1];
        const az = this.data[2];
        const aw = this.data[3];
        const bx = target[0];
        const by = target[1];
        const bz = target[2];
        const bw = target[3];
        const compare = (a, b) => Math.abs(a - b) <= tolerance * Math.max(1, Math.abs(a), Math.abs(b));

        const direct = compare(ax, bx) && compare(ay, by) && compare(az, bz) && compare(aw, bw);
        if (direct) {
            return true;
        }

        return compare(ax, -bx) && compare(ay, -by) && compare(az, -bz) && compare(aw, -bw);
    }

    getYaw() {
        const x = this.data[0];
        const y = this.data[1];
        const z = this.data[2];
        const w = this.data[3];
        const sinyCosp = 2 * (w * y + z * x);
        const cosyCosp = 1 - 2 * (x * x + y * y);
        return Math.atan2(sinyCosp, cosyCosp);
    }

    getPitch() {
        const x = this.data[0];
        const y = this.data[1];
        const z = this.data[2];
        const w = this.data[3];
        const sinp = 2 * (w * x - y * z);
        if (Math.abs(sinp) >= 1) {
            return Math.sign(sinp) * (Math.PI / 2);
        }
        return Math.asin(sinp);
    }

    getRoll() {
        const x = this.data[0];
        const y = this.data[1];
        const z = this.data[2];
        const w = this.data[3];
        const sinrCosp = 2 * (w * z + x * y);
        const cosrCosp = 1 - 2 * (x * x + z * z);
        return Math.atan2(sinrCosp, cosrCosp);
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
        return `Quat(${this.x}, ${this.y}, ${this.z}, ${this.w})`;
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

export default Quat;
