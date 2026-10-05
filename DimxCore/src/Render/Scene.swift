//
//  Location.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 12/07/2021.
//  Copyright © 2021 Dimensions. All rights reserved.
//

import Foundation
import Metal
import DimxNative

class Scene
{
    let id: Int
    let coreScene: UnsafeRawPointer
    let lighting: Lighting
    // Its ground shadow's targets, made by GroundShadowPass on first use.
    var groundShadowTarget: GroundShadowTarget? = nil
    var skyboxIrradianceMap: Texture? = nil
    var skyboxRadianceMap: Texture? = nil
    var skyboxRadianceMaxLod: Int = 0

    init(_ idx: Int, _ renderer: Renderer, _ ptr: UnsafeRawPointer) {
        id = idx
        coreScene = ptr
        lighting = Lighting(Scene_lighting(ptr))

        let skyboxPtr = Scene_skybox(ptr)
        if skyboxPtr != nil {
            let irradianceMapPtr = Skybox_irradianceMap(skyboxPtr)
            if irradianceMapPtr != nil {
                skyboxIrradianceMap = Renderer.instance.textures[Texture_nativeId(irradianceMapPtr!)]
            }
            let radianceMapPtr = Skybox_radianceMap(skyboxPtr)
            if radianceMapPtr != nil {
                skyboxRadianceMap = Renderer.instance.textures[Texture_nativeId(radianceMapPtr!)]
                skyboxRadianceMaxLod = max(Texture_numLods(radianceMapPtr) - 1, 0);
            }
        }
    }

    func coreId() -> UInt {
        return Scene_id(coreScene)
    }

    func onFrameUpdate() {
        lighting.onFrameUpdate()
    }
}
