import Vec3 from './Vec3.js';
import Quat from './Quat.js';
import Mat4 from './Mat4.js';

const glMatrix = globalThis.glMatrix;

if (!glMatrix || !glMatrix.mat4) {
    throw new Error('glMatrix global not found. Ensure gl-matrix-min.js is loaded before Transform.');
}

const { vec3, mat4 } = glMatrix;

const scratchMat = new Mat4();

export class Transform {
    constructor(position = new Vec3(),
                rotation = new Quat(),
                scale = new Vec3(1, 1, 1))
    {
        this.position = position;
        this.rotation = rotation;
        this.scale = scale;
    }

    static identity() {
        return new Transform();
    }

    static from(source) {
        return new Transform(source);
    }

    static isTransform(value) {
        return value instanceof Transform;
    }

    set(source) {
        if (source instanceof Transform) {
            return this.copy(source);
        }

        if (source === undefined || source === null) {
            throw new TypeError('Expected Transform-like value.');
        }

        if (source.position !== undefined) {
            this.setPosition(source.position);
        }

        if (source.rotation !== undefined) {
            this.setRotation(source.rotation);
        }

        if (source.scale !== undefined) {
            this.setScale(source.scale);
        }

        return this;
    }

    copy(source) {
        if (!(source instanceof Transform)) {
            return this.set(source);
        }

        this.position.copy(source.position);
        this.rotation.copy(source.rotation);
        this.scale.copy(source.scale);
        return this;
    }

    clone() {
        return new Transform(this);
    }

    identity() {
        this.position.set(0, 0, 0);
        this.rotation.identity();
        this.scale.set(1, 1, 1);
        return this;
    }

    setPosition(value) {
        this.position.set(value);
        return this;
    }

    setRotation(value) {
        this.rotation.set(value);
        this.rotation.normalize();
        return this;
    }

    setScale(value) {
        this.scale.set(value);
        return this;
    }

    translate(offset) {
        this.position.add(offset);
        return this;
    }

    rotate(quaternion) {
        this.rotation.multiply(quaternion);
        this.rotation.normalize();
        return this;
    }

    scaleBy(multiplier) {
        this.scale.multiply(multiplier);
        return this;
    }

    toMatrix(out = scratchMat) {
        if (out instanceof Mat4) {
            mat4.fromRotationTranslationScale(
                out.data,
                this.rotation.data,
                this.position.data,
                this.scale.data
            );
            return out;
        }

        return mat4.fromRotationTranslationScale(
            out,
            this.rotation.data,
            this.position.data,
            this.scale.data
        );
    }

    transformPoint(point, out = new Vec3()) {
        const mat = this.toMatrix();
        if (out instanceof Vec3) {
            vec3.transformMat4(out.data, point.data, mat.data);
            return out;
        }
        
        vec3.transformMat4(out, point.data, mat.data);
        return out;
    }

    toJSON() {
        return {
            position: this.position.toArray(),
            rotation: this.rotation.toArray(),
            scale: this.scale.toArray(),
        };
    }
}
