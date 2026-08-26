import Foundation
import Metal
import DimxNative

class Mesh
{
    var coreMesh: UnsafeRawPointer!
    var vertexBuffer: MTLBuffer!
    var primitiveType: MTLPrimitiveType = MTLPrimitiveType.triangle
    var indexBuffer: MTLBuffer?
    var numInds = 0
    var indexType: MTLIndexType = MTLIndexType.uint16

    var morphNumTargets = 0
    var morphIndsBuffer: MTLBuffer?
    var morphVertsBuffer: MTLBuffer?
    var morphNumVertComps = 0
    var morphEnabled = false
    var morphNormals = false
    var morphTangents = false
    
    var vertexDescriptor = MTLVertexDescriptor()

    // Everything that defines vertexDescriptor, in a form that can be compared and
    // hashed. Two meshes with the same attribute list, formats and stride produce
    // identical descriptors and can therefore share a pipeline state - see
    // Material.PipelineKey.
    private(set) var vertexLayoutKey: [Int] = []

    var numVerts = 0
    var numActiveVerts = 0
    var numActiveInds = 0

    // A dynamic mesh is rewritten every frame. It writes into one of a few
    // buffers in turn, so the CPU never overwrites what a frame still in
    // flight is reading, and only its active range is copied.
    private var dynamicBuffers: [MTLBuffer] = []
    private var dynamicIndex = 0
    private var dynamicCapacity = 0

    static func initCallbacks() {
        g_swiftMesh().pointee.createMesh = { (coreMat: Optional<UnsafeRawPointer>) -> (Int) in return Mesh.create(coreMat!) }
        g_swiftMesh().pointee.deleteMesh = { (id: Int) -> () in Mesh.delete(id) }
    }

    static func create(_ coreMat: UnsafeRawPointer) -> Int {
        Renderer.instance.meshes.append(Mesh(coreMat))
        return Renderer.instance.meshes.count - 1
    }

    static func delete(_ id: Int) {
        Renderer.instance.meshes[id] = nil
    }
    
    init(_ meshPtr: UnsafeRawPointer) {
        coreMesh = meshPtr

        primitiveType = primitiveTypeFromCore(Mesh_primitiveType(meshPtr))

        var offset = 0
        for i in 0 ..< Mesh_numVertexAttributes(meshPtr) {
            let attrPtr = Mesh_vertexAttribute(meshPtr, i)
            let enumIdx = VertexAttribute_type(attrPtr)
            let format = vertexFormatFromCore(VertexAttribute_elementType(attrPtr))
            vertexDescriptor.attributes[enumIdx].format = format
            vertexDescriptor.attributes[enumIdx].offset = offset
            vertexDescriptor.attributes[enumIdx].bufferIndex = VertexBufferIndex.VBIVertexBuffer.rawValue
            vertexLayoutKey.append(contentsOf: [enumIdx, Int(format.rawValue), offset])
            offset += VertexAttribute_elementSize(attrPtr)
        }
        let vertSize = Mesh_vertexSize(meshPtr)
        vertexDescriptor.layouts[0].stride = vertSize; // only one buffer is in use
        vertexLayoutKey.append(vertSize)

        if offset != vertSize {
            fatalError("Size of vertex attributes don't match. Offset [\(offset)] vertSize [\(vertSize)] ")
        }
       
        reloadMeshGeometry()
    }

    func draw(_ encoder: MTLRenderCommandEncoder) {
        
        if Mesh_dirtyFlag(coreMesh) {
            reloadMeshGeometry()
            Mesh_clearDirtyFlag(coreMesh)
        }
        
        if numActiveVerts == 0 {
            return;
        }

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: VertexBufferIndex.VBIVertexBuffer.rawValue)
        if morphIndsBuffer != nil {
            encoder.setVertexBuffer(morphIndsBuffer!, offset: 0, index: VertexBufferIndex.VBIMorphInds.rawValue)
        }
        if morphVertsBuffer != nil {
            encoder.setVertexBuffer(morphVertsBuffer!, offset: 0, index: VertexBufferIndex.VBIMorphVerts.rawValue)
        }
        if indexBuffer != nil {
            encoder.drawIndexedPrimitives(type: primitiveType,
                                          indexCount: numActiveInds,
                                          indexType: indexType,
                                          indexBuffer: indexBuffer!,
                                          indexBufferOffset: 0,
                                          instanceCount: 1,
                                          baseVertex: 0,
                                          baseInstance: 0)
        } else {
            encoder.drawPrimitives(type: primitiveType,
                                   vertexStart: 0,
                                   vertexCount: numActiveVerts,
                                   instanceCount: 1)
        }
    }
    
    // The dynamic path: the active vertices straight into the next buffer
    // of the ring, the indices once - a dynamic mesh writes them at build
    // and never again (see GlMesh::reloadMeshGeometry for the GL side).
    private func reloadDynamicGeometry(_ vertSize: Int) {
        let capacity = max(vertSize * numVerts, 16)
        if dynamicBuffers.isEmpty || dynamicCapacity < capacity {
            dynamicBuffers = (0 ..< 3).map { _ in Renderer.instance.device.makeBuffer(length: capacity, options: [.storageModeShared])! }
            dynamicCapacity = capacity
            dynamicIndex = 0
        }
        dynamicIndex = (dynamicIndex + 1) % dynamicBuffers.count
        vertexBuffer = dynamicBuffers[dynamicIndex]
        if numActiveVerts > 0 {
            let bytes = vertSize * numActiveVerts
            Mesh_fillVertexBufferRange(coreMesh, vertexBuffer.contents().assumingMemoryBound(to: CChar.self), bytes, numActiveVerts)
        }

        numInds = Mesh_numInds(coreMesh)
        if numInds > 0 {
            let indexBufferSize = Int(Mesh_indexBufferSize(coreMesh))
            if indexBuffer == nil || indexBuffer!.length != indexBufferSize {
                indexType = indexTypeFromCore(Mesh_indexType(coreMesh))
                indexBuffer = Renderer.instance.device.makeBuffer(bytes: Mesh_indexBufferData(coreMesh), length: indexBufferSize, options: [])
            }
        }
    }

    func reloadMeshGeometry() {
        numVerts = Mesh_numVerts(coreMesh)
        numActiveVerts = Mesh_numActiveVerts(coreMesh)
        numActiveInds = Mesh_numActiveInds(coreMesh)
        if numVerts == 0 {
            return;
        }
        if Mesh_dynamic(coreMesh) {
            reloadDynamicGeometry(Mesh_vertexSize(coreMesh))
            return
        }
            
        let vertSize = Mesh_vertexSize(coreMesh)

        var vertexData = [Int8](repeating: 0, count: vertSize * numVerts)
        Mesh_fillVertexBuffer(coreMesh, &vertexData, vertexData.count) // TODO: check the pointer is passed correctly
        
        if vertexBuffer == nil || vertexBuffer.length < vertexData.count {
            vertexBuffer = Renderer.instance.device.makeBuffer(bytes: vertexData, length: vertexData.count, options: [])
        } else {
            let bufferPointer = vertexBuffer.contents().assumingMemoryBound(to: Int8.self)
            vertexData.withUnsafeBufferPointer { pointer in
                bufferPointer.update(from: pointer.baseAddress!, count: vertexData.count)
            }
        }
          
        numInds = Mesh_numInds(coreMesh)
        if numInds > 0 {
            indexType = indexTypeFromCore(Mesh_indexType(coreMesh))
            let indexBufferSize = Int(Mesh_indexBufferSize(coreMesh))
            if indexBuffer == nil || indexBuffer!.length < indexBufferSize {
                indexBuffer = Renderer.instance.device.makeBuffer(bytes: Mesh_indexBufferData(coreMesh), length: indexBufferSize, options: [])
            } else {
                let dataPointer = Mesh_indexBufferData(coreMesh)!.bindMemory(to: Int8.self, capacity: indexBufferSize)
                let bufferPointer = indexBuffer!.contents().assumingMemoryBound(to: Int8.self)
                bufferPointer.update(from: dataPointer, count: indexBufferSize)
            }
        }
        
        let morphPtr = Mesh_morph(coreMesh)
        if morphPtr != nil {
            assert(METAL_MAX_MORPH_TARGETS_BLEND == MeshMorph_maxTargetsBlend(), "Mesh morph max targets blend mismatch!")
            morphNumTargets = MeshMorph_numTargets(morphPtr)
            if morphNumTargets > 0 {
                morphEnabled = true
                morphNormals = MeshMorph_hasNormals(morphPtr)
                morphTangents = MeshMorph_hasTangents(morphPtr)
                assert(numVerts == MeshMorph_numMeshVerts(morphPtr), "Number of verts mismatch")
                morphNumVertComps = MeshMorph_numVertComponents(morphPtr)
                let morphIndsSize = MeshMorph_indsDataSize(morphPtr)
                let morphVertsSize = MeshMorph_vertsDataSize(morphPtr)
                var morphIndsData = [Int8](repeating: 0, count: morphIndsSize)
                var morphVertsData = [Int8](repeating: 0, count: morphVertsSize)

                assert(MemoryLayout<Int32>.stride == MeshMorph_sizeOfIndex(morphPtr), "Size of morph index must match size of Int - 32bit");
                MeshMorph_populateDataBuffers(morphPtr, &morphIndsData, morphIndsData.count, &morphVertsData, morphVertsData.count)

                morphIndsBuffer = Renderer.instance.device.makeBuffer(bytes: morphIndsData, length: morphIndsData.count, options: [])
                morphVertsBuffer = Renderer.instance.device.makeBuffer(bytes: morphVertsData, length: morphVertsData.count, options: [])
            }
        }
    }
}
