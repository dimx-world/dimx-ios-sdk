import Vec3 from './Vec3.js';

export class Ray {
    constructor(origin, direction) {
        this.origin = origin;
        this.direction = direction;
    }

    clone() {
        return new Ray(this.origin, this.direction);
    }

    at(distance) {
        const result = this.origin.clone();
        result.scaleAndAdd(this.direction, distance);
        return result;
    }

    normalized() {
        return new Ray(this.origin, this.direction.clone().normalize());
    }

    normalize() {
        this.direction.normalize();
        return this;
    }

    closestDistToPoint(point) {
        const originToPoint = point.clone().subtract(this.origin);
        const t = originToPoint.dot(this.direction);
        const projectedPoint = this.at(t);
        return projectedPoint.distance(point);
    }

    toJSON() {
        return {
            origin: this.origin.toJSON(),
            direction: this.direction.toJSON(),
        };
    }
}
