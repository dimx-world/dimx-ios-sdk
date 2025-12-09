console.log("Loading global dimx module");

import {dimension} from 'dimx-cpp'
import * as gl_math from './lib/math/gl-matrix-min.js';
import {ContentFactory} from './lib/ContentFactory'
import {Vec2} from './lib/math/Vec2.js';
import {Vec3} from './lib/math/Vec3.js';
import {Vec4} from './lib/math/Vec4.js';
import {Quat} from './lib/math/Quat.js';
import {Mat4} from './lib/math/Mat4.js';
import {Transform} from './lib/math/Transform.js';
import {Ray} from './lib/math/Ray.js';

if (!globalThis.contentFactory) {
    globalThis.contentFactory = new ContentFactory();
    dimension.on('Dummy', '', globalThis.contentFactory.createContent.bind(contentFactory));
}

const content = globalThis.contentFactory;
import * as dimx_cpp from 'dimx-cpp'
const dimx_exports = { ...dimx_cpp, content, Vec2, Vec3, Vec4, Quat, Mat4, Transform, Ray };

if (!globalThis.dimx) {
    globalThis.dimx = dimx_exports;
}

//export default dimx_exports;
 