import {app} from 'dimx-cpp'

const Templates = []

const BaseConfig = {
    name: undefined,
    position: [0, 0, 0],
    rotation: [0, 0, 0],
    scale: 1,
    visible: true
}

function makeObjectConfig(parent, record) {
    return {
        parent: parent.id,
        name: record.name,
        visible: record.visible,
        transform: {
            position: record.position,
            rotation_angles: record.rotation,
            scale: record.scale
        }
    }
}

function makeInputConfig(record) {
    if (record.clickUrl) {
        return {
            onClick: () => app.openUrl(record.clickUrl)
        }
    }

    return undefined;
}

function makeFadeInConfig(record) {
    if (record.fadeIn) {
        return {
            property: 'Alpha',
            duration: 1,
            track: {
                values: [0, 1]
            }
        }
    }
    return undefined;
}

function makeFaceCameraConfig(record) {
    if (record.faceCamera) {
        return {
            type: 'FaceCamera'
        }
    } else if (record.doubleSided) {
        return {
            type: 'FaceCamera',
            fixed: true
        }
    }
    return undefined;
}

Templates.push({
    name: 'dummy',
    config: {
        ...BaseConfig,
        analytics: false
    },
    handler: (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Dummy: { analytics: record.analytics }
            }
        }
        parent.location.createObject(config)
    }
})

Templates.push({
    name: 'image',
    config: {
        ...BaseConfig,
        asset: "default",
        orientation: "Vertical", // Vertical, Horizontal
        width: 1,
        height: 1,
        transparent: false,
        fadeIn: true,
        receiveLighting: false,
        doubleSided: false,
        faceCamera: false,
        clickUrl: undefined,
        _meta_: {
            asset: {
                resource: 'Texture'
            }
        }
    },
    handler: async (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Image: {
                    asset: record.asset,
                    orientation: record.orientation,
                    width: record.width,
                    height: record.height,
                    transparent: record.transparent,
                    receiveLighting: record.receiveLighting,
                },
                Input: makeInputConfig(record),
                MaterialAnimator: makeFadeInConfig(record),
                FaceCamera: makeFaceCameraConfig(record)
            }
        }
        parent.location.createObject(config);
    }
})

Templates.push({
    name: 'model',
    config: {
        ...BaseConfig,
        asset: "box",
        animation: undefined,
        transparent: false,
        fadeIn: true,
        clickUrl: undefined,
        _meta_: {
            asset: {
                resource: 'Model'
            }
        }
    },
    handler: async (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Model: {
                    asset: record.asset,
                    animator: record.animation
                              ? { startAnimation: record.animation, loop: true }
                              : undefined
                },
                Input: makeInputConfig(record),
                MaterialAnimator: makeFadeInConfig(record),
                FaceCamera: makeFaceCameraConfig(record)
            }
        }

        //if (record.transparent) {
        //    config.ModelNode.materials = { ["1-0"]:  { transparent: true } }
        //}

        parent.location.createObject(config);
    }
})

Templates.push({
    name: 'audio',
    config: {
        ...BaseConfig,
        asset: '',
        coverImage: '',
        coverAlpha: 1.0,
        uiAlwaysOn: false,
        style: "Circle", // Flat, Circle
        progressText: false,
        width: 0.5,
        height: 0.5,
        autoplay: false,
        loop: false,
        sound3d: false,
        soundRefDist: 5,
        soundMaxDist: 15,
        fadeIn: true,
        doubleSided: false,
        faceCamera: false,
        _meta_: {
            asset: {
                resource: 'File'
            },
            coverImage: {
                resource: 'Texture'
            }
        }
    },
    handler: async (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Audio: {
                    asset: record.asset,
                    uiAlwaysOn: record.uiAlwaysOn,
                    style: record.style,
                    coverImage: record.coverImage,
                    coverAlpha: record.coverAlpha,
                    progressText: record.progressText,
                    width: record.width,
                    height: record.height,
                    autoplay: record.autoplay,
                    loop: record.loop,
                    sound3d: record.sound3d,
                    soundRefDist: record.soundRefDist,
                    soundMaxDist: record.soundMaxDist
                },
                MaterialAnimator: makeFadeInConfig(record),
                FaceCamera: makeFaceCameraConfig(record)
            }
        }

        parent.location.createObject(config)
    }
})

Templates.push({
    name: 'video',
    config: {
        ...BaseConfig,
        asset: null,
        width: 1.28,
        height: 0.72,
        autoplay: false,
        loop: false,
        sound3d: false,
        soundRefDist: 5,
        soundMaxDist: 15,
        fadeIn: true,
        doubleSided: false,
        faceCamera: false,
        alphaMatte: false,
        _meta_: {
            asset: {
                resource: 'File'
            }
        }
    },
    handler: async (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Video: {
                    asset: record.asset ? record.asset : '',
                    width: record.width,
                    height: record.height,
                    autoplay: record.autoplay,
                    loop: record.loop,
                    sound3d: record.sound3d,
                    soundRefDist: record.soundRefDist,
                    soundMaxDist: record.soundMaxDist,
                    alphaMatte: record.alphaMatte
                },
                MaterialAnimator: makeFadeInConfig(record),
                FaceCamera: makeFaceCameraConfig(record)
            }
        }
        parent.location.createObject(config)
    }
})

Templates.push({
    name: 'text',
    config: {
        ...BaseConfig,
        text: 'Text',
        fontSize: 20,
        framePadding: 0,
        frameWidth: 0,
        frameHeight: 0,
        borderSize: 0,
        cornerRadius: 0,

        color: '1 1 1 1',
        backgroundColor: '0 0 0 0',
        borderColor: '1 1 1 1',

        fadeIn: true,
        receiveLighting: true,
        doubleSided: false,
        faceCamera: false
    },
    handler: async (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Text: {
                    text: record.text,
                    fontSize: record.fontSize,
                    framePadding: record.framePadding,
                    frameWidth: record.frameWidth,
                    frameHeight: record.frameHeight,
                    borderSize: record.borderSize,
                    cornerRadius: record.cornerRadius,
                    color: record.color,
                    backgroundColor: record.backgroundColor,
                    borderColor: record.borderColor,
                    receiveLighting: record.receiveLighting
                },
                MaterialAnimator: makeFadeInConfig(record),
                FaceCamera: makeFaceCameraConfig(record)
            }
        }
        parent.location.createObject(config)
    }
})

Templates.push({
    name: 'trigger',
    config: {
        ...BaseConfig,
        radius: 3,
        once: false,
        onEnter: null,
        onExit: null
    },
    handler: (parent, record) => {
        let config = {
            ...makeObjectConfig(parent, record),
            components: {
                Trigger: {
                    radius: record.radius,
                    once: record.once,
                    onEnter: record.onEnter,
                    onExit: record.onExit
                }
            }
        }
        parent.location.createObject(config)
    }
})

export { Templates };