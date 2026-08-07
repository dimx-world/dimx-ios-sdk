#include "ImGuiContextInterface.h"
#include <Engine.h>
#include <ui/imgui/ImGuiContextWrapper.h>
#include <imgui/imgui.h>

namespace {
ImDrawData* drawDataOf(const void* ptr)
{
    return reinterpret_cast<const ImGuiContextWrapper*>(ptr)->drawData();
}
} // namespace

void* ImGuiContext_mesh(const void* ptr)
{
    return reinterpret_cast<const ImGuiContextWrapper*>(ptr)->mesh().get();
}

long ImGuiContext_vertexSize(const void* ptr)
{
    return reinterpret_cast<const ImGuiContextWrapper*>(ptr)->vertexSize();;
}

long ImGuiContext_indexSize(const void* ptr)
{
    return reinterpret_cast<const ImGuiContextWrapper*>(ptr)->indexSize();;
}

const void* ImGuiContext_mvpMat(const void* ptr)
{
    return &reinterpret_cast<const ImGuiContextWrapper*>(ptr)->mvpMat();
}

long ImGuiContext_numDrawCalls(const void* ptr)
{
    return static_cast<long>(reinterpret_cast<const ImGuiContextWrapper*>(ptr)->drawCalls().size());
}

const ImGuiDrawCall* ImGuiContext_drawCall(const void* ptr, long index)
{
    return &reinterpret_cast<const ImGuiContextWrapper*>(ptr)->drawCalls().at(index);
}

const void* ImGuiContext_renderTarget(const void* ptr)
{
    return reinterpret_cast<const ImGuiContextWrapper*>(ptr)->renderTarget();
}

long ImGuiContext_frameCounter(const void* ptr)
{
    return static_cast<long>(reinterpret_cast<const ImGuiContextWrapper*>(ptr)->frameCounter());
}

long ImGuiContext_numTextures(const void* ptr)
{
    ImDrawData* drawData = drawDataOf(ptr);
    if (!drawData || drawData->Textures == nullptr) {
        return 0;
    }
    return static_cast<long>(drawData->Textures->Size);
}

void* ImGuiContext_texture(const void* ptr, long index)
{
    ImDrawData* drawData = drawDataOf(ptr);
    return (*drawData->Textures)[static_cast<int>(index)];
}

int ImTexture_wantCreate(const void* tex)
{
    return reinterpret_cast<const ImTextureData*>(tex)->Status == ImTextureStatus_WantCreate ? 1 : 0;
}

int ImTexture_wantUpdates(const void* tex)
{
    return reinterpret_cast<const ImTextureData*>(tex)->Status == ImTextureStatus_WantUpdates ? 1 : 0;
}

int ImTexture_wantDestroy(const void* tex)
{
    const ImTextureData* t = reinterpret_cast<const ImTextureData*>(tex);
    return (t->Status == ImTextureStatus_WantDestroy && t->UnusedFrames > 0) ? 1 : 0;
}

int ImTexture_width(const void* tex)
{
    return reinterpret_cast<const ImTextureData*>(tex)->Width;
}

int ImTexture_height(const void* tex)
{
    return reinterpret_cast<const ImTextureData*>(tex)->Height;
}

const void* ImTexture_pixels(const void* tex)
{
    return const_cast<ImTextureData*>(reinterpret_cast<const ImTextureData*>(tex))->GetPixels();
}

unsigned long long ImTexture_texId(const void* tex)
{
    return static_cast<unsigned long long>(reinterpret_cast<const ImTextureData*>(tex)->TexID);
}

void ImTexture_setCreated(void* tex, unsigned long long texId)
{
    ImTextureData* t = reinterpret_cast<ImTextureData*>(tex);
    t->SetTexID(static_cast<ImTextureID>(texId));
    t->SetStatus(ImTextureStatus_OK);
}

void ImTexture_setUpdated(void* tex)
{
    reinterpret_cast<ImTextureData*>(tex)->SetStatus(ImTextureStatus_OK);
}

void ImTexture_setDestroyed(void* tex)
{
    ImTextureData* t = reinterpret_cast<ImTextureData*>(tex);
    t->SetTexID(ImTextureID_Invalid);
    t->SetStatus(ImTextureStatus_Destroyed);
}
