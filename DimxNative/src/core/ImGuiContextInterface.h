#ifndef IM_GUI_CONTEXT_INTERFACE_H_INCLUDED
#define IM_GUI_CONTEXT_INTERFACE_H_INCLUDED

#include <ui/imgui/ImGuiDrawCall.h>

#ifdef __cplusplus
extern "C" {
#endif

void* ImGuiContext_mesh(const void* ptr);
long ImGuiContext_vertexSize(const void* ptr);
long ImGuiContext_indexSize(const void* ptr);
const void* ImGuiContext_mvpMat(const void* ptr);
long ImGuiContext_numDrawCalls(const void* ptr);
const ImGuiDrawCall* ImGuiContext_drawCall(const void* ptr, long index);
const void* ImGuiContext_renderTarget(const void* ptr);
long ImGuiContext_frameCounter(const void* ptr);

// ImGui 1.92 dynamic font-atlas texture queue (ImDrawData::Textures). The Metal backend services
// these entries before rendering so every ImTextureData referenced by the draw calls has a valid
// backend id (stored in ImTextureData::TexID via ImTexture_setCreated).
long ImGuiContext_numTextures(const void* ptr);
void* ImGuiContext_texture(const void* ptr, long index);

int ImTexture_wantCreate(const void* tex);
int ImTexture_wantUpdates(const void* tex);
int ImTexture_wantDestroy(const void* tex);   // true only once the texture has gone unused
int ImTexture_width(const void* tex);
int ImTexture_height(const void* tex);
const void* ImTexture_pixels(const void* tex);          // tightly-packed RGBA32, row stride = width*4
unsigned long long ImTexture_texId(const void* tex);
void ImTexture_setCreated(void* tex, unsigned long long texId); // SetTexID + status OK
void ImTexture_setUpdated(void* tex);                           // status OK
void ImTexture_setDestroyed(void* tex);                         // SetTexID(invalid) + status Destroyed

#ifdef __cplusplus
}
#endif

#endif // IM_GUI_INTERFACE_H_INCLUDED
