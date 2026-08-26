#ifndef MESH_INTERFACE_H_INCLUDED
#define MESH_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

long Mesh_numVerts(const void* ptr);
long Mesh_numActiveVerts(const void* ptr);
// Whether the mesh is rewritten while it lives - uploaded per frame, active range only.
bool Mesh_dynamic(const void* ptr);

long Mesh_vertexSize(const void* ptr);
long Mesh_numVertexAttributes(const void* ptr);
const void* Mesh_vertexAttribute(const void* ptr, long index);
void Mesh_fillVertexBuffer(const void* ptr, char* outBuffer, long outBufferSize);
void Mesh_fillVertexBufferRange(const void* ptr, char* outBuffer, long outBufferSize, long numVerts);

long Mesh_indexType(const void* ptr);
long Mesh_numInds(const void* ptr);
long Mesh_numActiveInds(const void* ptr);
const void* Mesh_indexBufferData(const void* ptr);
long Mesh_indexBufferSize(const void* ptr);

long Mesh_primitiveType(const void* ptr);

long Mesh_nativeId(const void* ptr);

const void* Mesh_morph(const void* ptr);

bool Mesh_dirtyFlag(const void* ptr);
void Mesh_clearDirtyFlag(const void* ptr);

#ifdef __cplusplus
}
#endif

#endif // MESH_INTERFACE_H_INCLUDED
