#ifndef IOS_RENDERER_INCLUDED_H_INCLUDED
#define IOS_RENDERER_INCLUDED_H_INCLUDED

//---------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

struct SwiftRenderer
{
    void (*initialize)(const void*);
    void (*postInit)(const void*);
    void (*beginFrame)(const void*);
    // Returns whether the frame actually reached the screen. A frame with no
    // layer or no drawable is dropped, and the update loop must not mistake one
    // for a presented frame - presenting is the only thing pacing it.
    bool (*endFrame)();
    void (*getFrameImageData)(long, long, void*);

    long (*createScene)(const void*);
    void (*deleteScene)(long);
};
struct SwiftRenderer* g_swiftRenderer();

// The frame capture (Renderer: frame capture), for Renderer.endFrame: whether
// this frame's capture is wanted at all, whether a photo of it is, and the
// photo's pixels - RGBA, the top row first - once the GPU has written them.
bool Renderer_capturing();
bool Renderer_photoRequested();
void Renderer_photoCaptured(const void* rgba, long width, long height);

long Renderer_linesVertsCount(bool debugBuffer);
const void* Renderer_linesVertsData(bool debugBuffer);
long Renderer_linesPolyVertsCount(bool debugBuffer);
const void* Renderer_linesPolyVertsData(bool debugBuffer);
// What the debug pass holds a frame, in vertices - 0 lines, 1 polygons, 2 dots - as the render
// config's `debug` block says (RenderLines::capacities): what DebugPass sizes its buffers by.
long Renderer_debugCapacity(int kind);
// The dots (RenderLines::drawDot): one vertex each, drawn as a point of Renderer_dotSize pixels.
long Renderer_dotsCount(bool debugBuffer);
const void* Renderer_dotsData(bool debugBuffer);
float Renderer_dotSize(bool debugBuffer);
// The textured quads (RenderLines::drawTexturedQuad): a quad's four corners - 12 floats, the
// picture's top left, top right, bottom right, bottom left - its texture coordinates (uvMin.x,
// uvMin.y, uvMax.x, uvMax.y), its opacity, whether its texture's colour is multiplied by its
// alpha already (an SVG tile) and its texture's native id; false past the list.
long Renderer_quadsCount(bool debugBuffer);
bool Renderer_quad(bool debugBuffer, long index, float* corners, float* uv, float* alpha, bool* premultiplied, long* textureId);
// The geometry held across frames (RenderLines::setSurface, addCloud): the surface - triangles,
// three vertices each - and this frame's clouds - a point each - as their vertices (DebugVertex:
// xyz rgba, 7 floats), their identity (DebugMeshData::id - the same id is the same vertices,
// so the pass uploads a piece once and draws what it holds), where each stands (16 floats,
// column-major), the opacity it is drawn at and, for a cloud, its points' size in pixels. False
// when there is no surface, or past the clouds.
bool Renderer_heldSurface(const void** data, long* count, long* id, float* transform, float* opacity);
long Renderer_heldCloudsCount();
bool Renderer_heldCloud(long index, const void** data, long* count, long* id, float* transform, float* pointPixels, float* opacity);
void Renderer_drawPoint(bool debugBuffer, const void* posPtr, float worldSize, const void* colPtr);
void Renderer_drawLine(bool debugBuffer, const void* pos1Ptr, const void* col1Ptr, const void* pos2Ptr, const void* col2Ptr);
void Renderer_drawLineRect(bool debugBuffer, float width, float height, const void* transformPtr, const void* colPtr);
void Renderer_drawLineBox(bool debugBuffer, const void* minPtr, const void* maxPtr, const void* transformPtr, const void* colPtr);
void Renderer_drawTriangle(bool debugBuffer, const void* pos1Ptr, const void* pos2Ptr, const void* pos3Ptr, const void* colPtr);
void Renderer_drawPose(bool debugBuffer, const void* transformPtr, float size);

//---- Sample code how to pass swift callback into c++

//typedef void (*TestFunc)(const RendererConfig *);
typedef unsigned long (*TestFunc)(const void*);
void testCallback(TestFunc func);

#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus
//---------------------------------------------------------------

#ifdef __cplusplus
#include <render/Renderer.h>

class IOSRenderer: public Renderer
{
public:
    void initialize(const Variant& config) override;
    void postInit(const Variant& config, CounterPtr counter) override;
    void deinitialize() override;
    
    void beginFrame(const FrameContext& frameContext) override;
    void endFrame(const FrameContext& frameContext) override;

    void getFrameImageData(int width, int height, Buffer& outBuffer) override;

    std::unique_ptr<NativeTexture> createTexture(const Texture& coreTexture) override;
    std::unique_ptr<NativeMaterial> createMaterial(const Material& coreMaterial) override;
    std::unique_ptr<NativeMesh> createMesh(const Mesh& coreMesh) override;
    std::unique_ptr<NativeRenderable> createRenderable(const Renderable& coreRenderable) override;
    std::unique_ptr<NativeScene> createScene(const Scene& coreScene) override;
    void deleteScene(size_t id) override;

    // Whether the last endFrame reached the screen. The update loop paces itself
    // on a presented drawable, so it has to know this rather than infer it from
    // live mode - a dropped frame leaves nothing to block on and would spin.
    bool framePresented() const { return mFramePresented; }
    void clearFramePresented() { mFramePresented = false; }

    // The capture, for the Swift side (the C functions above). A photo asked
    // for is taken once: the request stands until the GPU has delivered it,
    // and the frames in between take no second copy.
    bool wantsPhoto() { if (!photoRequested() || mPhotoInFlight) { return false; } mPhotoInFlight = true; return true; }
    void photoCaptured(const void* rgba, long width, long height);

private:
    bool mFramePresented = false;
    bool mPhotoInFlight = false;
};
#endif // __cplusplus

#endif // IOS_RENDERER_INCLUDED_H_INCLUDED
