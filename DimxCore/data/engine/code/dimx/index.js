// Wrap the native string-only logger so user code can call console.log(obj, n, ...)
// the way it works in browsers / Node.
(function installConsole() {
    const native = globalThis._nativeConsole;
    if (!native) {
        return;
    }

    function fmt(args) {
        return args.map(a => {
            if (a === null || a === undefined) {
                return String(a);
            }
            if (typeof a === 'string') {
                return a;
            }
            if (typeof a === 'object') {
                try {
                    return JSON.stringify(a);
                } catch {
                    return String(a);
                }
            }
            return String(a);
        }).join(' ');
    }

    globalThis.console = {
        log:   (...a) => native.log(fmt(a)),
        info:  (...a) => native.info(fmt(a)),
        debug: (...a) => native.debug(fmt(a)),
        warn:  (...a) => native.warn(fmt(a)),
        error: (...a) => native.error(fmt(a)),
    };
    delete globalThis._nativeConsole;
})();

console.log("Loading global dimx module");

import {dimension} from 'dimx-cpp';
import './lib/math/gl-matrix-min.js';
import {ContentFactory} from './lib/ContentFactory';
import {Vec2} from './lib/math/Vec2.js';
import {Vec3} from './lib/math/Vec3.js';
import {Vec4} from './lib/math/Vec4.js';
import {Quat} from './lib/math/Quat.js';
import {Mat4} from './lib/math/Mat4.js';
import {Transform} from './lib/math/Transform.js';
import {Ray} from './lib/math/Ray.js';

// Re-export the native bindings (dimension, timer, app, Entity, Vec3Like, ...)
export * from 'dimx-cpp';

// Math helpers (these shadow any same-named re-exports from dimx-cpp — intended).
export {Vec2, Vec3, Vec4, Quat, Mat4, Transform, Ray};

if (!globalThis.contentFactory) {
    globalThis.contentFactory = new ContentFactory();
    dimension.on('Dummy', '', globalThis.contentFactory.createContent.bind(globalThis.contentFactory));
}

export const content = globalThis.contentFactory;
