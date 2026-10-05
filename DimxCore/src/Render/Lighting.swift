//
//  Lighting.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 12/07/2021.
//  Copyright © 2021 Dimensions. All rights reserved.
//

import Foundation
import Metal
import simd
import DimxNative
class Lighting
{
    let coreLighting: UnsafeRawPointer

    let enabled = true

    var ambientColor = vector_float3()
    var diffuseColor = vector_float3()
    var specularColor = vector_float3()

    var direction = vector_float3()

    init(_ ptr: UnsafeRawPointer) {
        coreLighting = ptr

        Lighting_ambientColor(coreLighting, &ambientColor)
        Lighting_diffuseColor(coreLighting, &diffuseColor)
        Lighting_specularColor(coreLighting, &specularColor)

        onFrameUpdate()
    }

    func onFrameUpdate() {
        Lighting_direction(coreLighting, &direction)
    }
}
