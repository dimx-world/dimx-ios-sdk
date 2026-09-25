import Foundation
import simd
import DimxNative

func getVariantStr(configPtr: UnsafeRawPointer, key: String) -> String
{
    var strBuf = [Int8](repeating: 0, count: 256)
    if Variant_getStr(configPtr, key, &strBuf, UInt32(strBuf.count)) >= 0 {
        return String(cString: strBuf)
    }
    fatalError("Invalid config key [\(key)]")
}

func getVariantVec3(configPtr: UnsafeRawPointer, key: String) -> simd_float3
{
    var tmp = simd_float3()
    Variant_getVec3(configPtr, key, &tmp)
    return tmp
}

func getVariantVec4(configPtr: UnsafeRawPointer, key: String) -> simd_float4
{
    var tmp = simd_float4()
    Variant_getVec4(configPtr, key, &tmp)
    return tmp
}
