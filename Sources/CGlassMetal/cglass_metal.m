// The Liquid Glass program on Apple's Metal (ADR-0052 stage 2). See cglass_metal.h.
// Written to work with and without ARC.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <string.h>
#include "cglass_metal.h"

#if __has_feature(objc_arc)
#define CGM_RETAIN(x) (x)
#define CGM_RELEASE(x) ((void)0)
#define CGM_BRIDGE_RETAINED(x) ((__bridge_retained void *)(x))
#define CGM_BRIDGE_TRANSFER(x) ((__bridge_transfer id)(x))
#define CGM_BRIDGE(x) ((__bridge id)(x))
#else
#define CGM_RETAIN(x) [(x) retain]
#define CGM_RELEASE(x) [(x) release]
#define CGM_BRIDGE_RETAINED(x) ((void *)[(x) retain])
#define CGM_BRIDGE_TRANSFER(x) ([(id)(x) autorelease])
#define CGM_BRIDGE(x) ((id)(x))
#endif

struct CGMProgram {
    void *device;      // id<MTLDevice>
    void *queue;       // id<MTLCommandQueue>
    void *box, *saturate, *luminance, *lens;   // id<MTLComputePipelineState>
    char name[256];
};

typedef struct { uint32_t width, height, stride, radius, horizontal, pad0, pad1, pad2; } CGMPass;

static void cgm_error(char *error, size_t cap, NSString *message) {
    if (!error || cap == 0) return;
    strncpy(error, message.UTF8String ?: "unknown error", cap - 1);
    error[cap - 1] = 0;
}

static void *cgm_pipeline(id<MTLDevice> device, id<MTLLibrary> library, NSString *name, char *error, size_t cap) {
    id<MTLFunction> f = [library newFunctionWithName:name];
    if (!f) { cgm_error(error, cap, [NSString stringWithFormat:@"no function %@", name]); return NULL; }
    NSError *e = nil;
    id<MTLComputePipelineState> p = [device newComputePipelineStateWithFunction:f error:&e];
    CGM_RELEASE(f);
    if (!p) { cgm_error(error, cap, e.localizedDescription ?: @"pipeline failed"); return NULL; }
    return CGM_BRIDGE_RETAINED(p);
}

CGMProgram *cgm_program_create(const char *source, char *error, size_t cap) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { cgm_error(error, cap, @"no Metal device"); return NULL; }
        MTLCompileOptions *options = [MTLCompileOptions new];
        if (@available(macOS 15.0, *)) { options.mathMode = MTLMathModeSafe; } else { options.fastMathEnabled = NO; }
        NSError *e = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:[NSString stringWithUTF8String:source] options:options error:&e];
        CGM_RELEASE(options);
        if (!library) { cgm_error(error, cap, e.localizedDescription ?: @"compile failed"); CGM_RELEASE(device); return NULL; }
        CGMProgram *p = calloc(1, sizeof(CGMProgram));
        p->box = cgm_pipeline(device, library, @"glass_box", error, cap);
        p->saturate = p->box ? cgm_pipeline(device, library, @"glass_saturate", error, cap) : NULL;
        p->luminance = p->saturate ? cgm_pipeline(device, library, @"glass_luminance", error, cap) : NULL;
        p->lens = p->luminance ? cgm_pipeline(device, library, @"glass_lens", error, cap) : NULL;
        CGM_RELEASE(library);
        id<MTLCommandQueue> queue = p->lens ? [device newCommandQueue] : nil;
        if (!queue) {
            if (p->lens) cgm_error(error, cap, @"no command queue");
            p->device = CGM_BRIDGE_RETAINED(device);
            CGM_RELEASE(device);
            cgm_program_release(p);
            return NULL;
        }
        p->device = CGM_BRIDGE_RETAINED(device);
        p->queue = CGM_BRIDGE_RETAINED(queue);
        CGM_RELEASE(queue);
        strncpy(p->name, device.name.UTF8String ?: "Metal", sizeof(p->name) - 1);
        CGM_RELEASE(device);
        return p;
    }
}

void cgm_program_release(CGMProgram *p) {
    if (!p) return;
    void *objects[] = {p->box, p->saturate, p->luminance, p->lens, p->queue, p->device};
    for (size_t i = 0; i < sizeof(objects) / sizeof(objects[0]); i++) if (objects[i]) (void)CGM_BRIDGE_TRANSFER(objects[i]);
    free(p);
}

const char *cgm_program_device_name(CGMProgram *p) { return p ? p->name : ""; }

static void cgm_dispatch(id<MTLComputeCommandEncoder> enc, void *pipeline, uint32_t w, uint32_t h) {
    id<MTLComputePipelineState> ps = CGM_BRIDGE(pipeline);
    [enc setComputePipelineState:ps];
    MTLSize group = MTLSizeMake(8, 8, 1);
    [enc dispatchThreadgroups:MTLSizeMake((w + 7) / 8, (h + 7) / 8, 1) threadsPerThreadgroup:group];
}

bool cgm_program_run(CGMProgram *p, const uint8_t *raw, uint32_t width, uint32_t height, uint32_t stride,
                     bool runBackdropStage, uint32_t boxRadius, const float *constants,
                     uint8_t *out, uint32_t outWidth, uint32_t outHeight, float *luminanceOut) {
    if (!p || !raw || !out || width == 0 || height == 0 || outWidth == 0 || outHeight == 0 || stride % 4 != 0) return false;
    @autoreleasepool {
        id<MTLDevice> device = CGM_BRIDGE(p->device);
        id<MTLCommandQueue> queue = CGM_BRIDGE(p->queue);
        NSUInteger bytes = (NSUInteger)stride * height;
        id<MTLBuffer> a = [device newBufferWithBytes:raw length:bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> b = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        id<MTLBuffer> o = [device newBufferWithLength:(NSUInteger)outWidth * outHeight * 4 options:MTLResourceStorageModeShared];
        id<MTLBuffer> lum = [device newBufferWithLength:16 options:MTLResourceStorageModeShared];
        if (!a || !b || !o || !lum) { CGM_RELEASE(a); CGM_RELEASE(b); CGM_RELEASE(o); CGM_RELEASE(lum); return false; }
        ((float *)lum.contents)[0] = -1;
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
        [enc setBytes:constants length:48 * sizeof(float) atIndex:2];
        CGMPass pass = {width, height, stride / 4, boxRadius, 0, 0, 0, 0};
        // The blurred pixels end in `a`: each of the three rounds runs a -> b across, b -> a down.
        if (runBackdropStage) {
            if (boxRadius > 0) {
                for (int i = 0; i < 3; i++) {
                    pass.horizontal = 1;
                    [enc setBuffer:a offset:0 atIndex:0]; [enc setBuffer:b offset:0 atIndex:1];
                    [enc setBytes:&pass length:sizeof(pass) atIndex:3];
                    cgm_dispatch(enc, p->box, width, height);
                    pass.horizontal = 0;
                    [enc setBuffer:b offset:0 atIndex:0]; [enc setBuffer:a offset:0 atIndex:1];
                    [enc setBytes:&pass length:sizeof(pass) atIndex:3];
                    cgm_dispatch(enc, p->box, width, height);
                }
            }
            [enc setBytes:&pass length:sizeof(pass) atIndex:3];
            if (constants[39] != 1) {
                [enc setBuffer:a offset:0 atIndex:1];
                cgm_dispatch(enc, p->saturate, width, height);
            }
            [enc setBuffer:a offset:0 atIndex:1];
            [enc setBuffer:lum offset:0 atIndex:4];
            [enc setComputePipelineState:CGM_BRIDGE(p->luminance)];
            [enc dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(256, 1, 1)];
        }
        [enc setBytes:&pass length:sizeof(pass) atIndex:3];
        [enc setBuffer:a offset:0 atIndex:0];
        [enc setBuffer:o offset:0 atIndex:1];
        [enc setBuffer:lum offset:0 atIndex:4];
        cgm_dispatch(enc, p->lens, outWidth, outHeight);
        [enc endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        bool ok = cb.status == MTLCommandBufferStatusCompleted;
        if (ok) {
            memcpy(out, o.contents, (size_t)outWidth * outHeight * 4);
            if (luminanceOut) *luminanceOut = ((float *)lum.contents)[0];
        }
        CGM_RELEASE(a); CGM_RELEASE(b); CGM_RELEASE(o); CGM_RELEASE(lum);
        return ok;
    }
}
