// Read Apple's on-disk resources, never the currently registered custom theme.
// CursorAsset layout independently checked on macOS 26.6.2.
#import <mach-o/getsect.h>
typedef struct { uint64_t identifier; const void *record; } MeowAssetEntry;
typedef struct {
    double width, height, hotX, hotY;
    uint64_t frames;
    float duration;
    uint32_t padding;
    uint64_t representationCount;
    const void *representations[];
} MeowAssetRecord;
typedef struct { uint64_t width, height; double hotX, hotY; uint8_t pixels[]; } MeowAssetPixels;

static NSDictionary *nativeDefaults(void) {
    const char *path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/CursorAsset";
    void *library = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    const MeowAssetEntry *table = library ? dlsym(library, "cursors") : NULL;
    Dl_info location;
    if (!table || !dladdr(table, &location)) fail(@"Cannot read Apple's CursorAsset. No cursors changed.");
    unsigned long bytes = 0;
    const uint8_t *section = getsectiondata(location.dli_fbase, "__DATA_CONST", "__const", &bytes);
    if (!section || (const uint8_t *)table < section || (const uint8_t *)table >= section + bytes)
        fail(@"Unsupported CursorAsset table layout. No cursors changed.");
    NSUInteger entries = (section + bytes - (const uint8_t *)table) / sizeof(MeowAssetEntry);
    BOOL modern = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26;
    NSDictionary *wanted = modern ? @{@100: @"com.apple.coregraphics.ArrowS", @101: @"com.apple.coregraphics.IBeamS", @7: waitCursor}
                                  : @{@0: @"com.apple.coregraphics.Arrow", @1: @"com.apple.coregraphics.IBeam", @7: waitCursor};
    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < entries && table[i].record; i++) {
        NSString *key = wanted[@(table[i].identifier)];
        if (!key) continue;
        const MeowAssetRecord *r = table[i].record;
        if (r->frames < 1 || r->frames > 128 || r->representationCount < 1 || r->representationCount > 8 ||
            !isfinite(r->width) || !isfinite(r->height) || r->width <= 0 || r->width > 512 || r->height <= 0 || r->height > 512)
            fail(@"Unsupported native cursor record. No cursors changed.");
        BOOL sampleWait = [key isEqualToString:waitCursor] && r->frames == nativeWaitFrames;
        NSUInteger outputFrames = sampleWait ? compatibleWaitFrames : r->frames;
        NSMutableArray *representations = [NSMutableArray array];
        for (NSUInteger j = 0; j < r->representationCount; j++) {
            const MeowAssetPixels *p = r->representations[j];
            if (!p || p->width < 1 || p->width > 2048 || p->height < 1 || p->height > 2048)
                fail(@"Unsupported native cursor pixels. No cursors changed.");
            CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, p->pixels, p->width * p->height * r->frames * 4, NULL);
            CGImageRef image = CGImageCreate(p->width, p->height * r->frames, 8, 32, p->width * 4, color,
                kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, NULL, false, kCGRenderingIntentDefault);
            if (image && sampleWait) {
                CGImageRef sampled = sampleNativeWait(image);
                CGImageRelease(image);
                image = sampled;
            }
            NSData *png = image ? [[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
            if (image) CGImageRelease(image);
            CGDataProviderRelease(provider); CGColorSpaceRelease(color);
            if (!png) fail(@"Cannot decode native cursor pixels. No cursors changed.");
            [representations addObject:png];
        }
        cursors[key] = @{@"PointsWide": @(r->width), @"PointsHigh": @(r->height), @"HotSpotX": @(r->hotX), @"HotSpotY": @(r->hotY),
                         @"FrameCount": @(outputFrames), @"FrameDuration": @(r->duration * (double)r->frames / outputFrames),
                         @"NativeSourceFrames": @(r->frames), @"Representations": representations};
    }
    if (cursors.count != 3) fail(@"Native arrow, text or wait asset not found. No cursors changed.");
    // The pointing-hand artwork and hotspot come from HIServices, not a theme dump.
    NSString *directory = @"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Resources/cursors/pointinghand";
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"info.plist"]];
    NSImage *pdf = [[NSImage alloc] initWithContentsOfFile:[directory stringByAppendingPathComponent:@"cursor.pdf"]];
    if (!pdf || !info[@"hotx"] || !info[@"hoty"]) fail(@"Cannot read Apple's pointing-hand resource.");
    NSSize size = pdf.size;
    NSMutableArray *reps = [NSMutableArray array];
    for (NSNumber *density in @[@1, @2]) {
        CGFloat scale = density.doubleValue;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:lround(size.width * scale)
            pixelsHigh:lround(size.height * scale) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        bitmap.size = size;
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        NSShadow *shadow = [NSShadow new];
        NSArray *rgba = info[@"shadowcolor"];
        if (rgba.count == 4) shadow.shadowColor = [NSColor colorWithSRGBRed:[rgba[0] doubleValue] green:[rgba[1] doubleValue] blue:[rgba[2] doubleValue] alpha:[rgba[3] doubleValue]];
        shadow.shadowBlurRadius = [info[@"blur"] doubleValue];
        shadow.shadowOffset = NSMakeSize([info[@"shadowoffsetx"] doubleValue], [info[@"shadowoffsety"] doubleValue]);
        [shadow set];
        [pdf drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!png) fail(@"Cannot render Apple's pointing-hand resource.");
        [reps addObject:png];
    }
    cursors[@"com.apple.cursor.13"] = @{@"PointsWide": @(size.width), @"PointsHigh": @(size.height), @"HotSpotX": info[@"hotx"], @"HotSpotY": info[@"hoty"],
                                       @"FrameCount": @1, @"FrameDuration": @0, @"Representations": reps};
    return cursors;
}
