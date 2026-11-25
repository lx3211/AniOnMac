#define CURSORCTL_TEST
#include "../native/cursorctl.m"
#include <assert.h>

static void testNativeWaitBackup(NSString *path, NSDictionary *stockWait) {
    NSBitmapImageRep *sheet = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:2 pixelsHigh:nativeWaitFrames bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger frame = 0; frame < nativeWaitFrames; frame++) {
        NSUInteger pixel[] = {(NSUInteger)frame * 8, 0, 0, 255};
        [sheet setPixel:pixel atX:0 y:frame];
        [sheet setPixel:pixel atX:1 y:frame];
    }
    NSMutableDictionary *rawWait = [stockWait mutableCopy];
    rawWait[@"FrameCount"] = @(nativeWaitFrames);
    rawWait[@"FrameDuration"] = @(1.0 / 60);
    rawWait[@"Representations"] = @[[sheet representationUsingType:NSBitmapImageFileTypePNG properties:@{}]];
    assert(saveBackup(@{waitCursor: rawWait}, path, YES, NULL));

    NSDictionary *backup = readCape(path, YES);
    assert([backup[waitCursor] isEqual:rawWait]);
    NSDictionary *restored = restorableCursors(backup)[waitCursor];
    assert([restored[@"FrameCount"] unsignedIntegerValue] == compatibleWaitFrames);
    assert(fabs([restored[@"FrameDuration"] doubleValue] * compatibleWaitFrames - 0.5) < 0.000001);
    for (NSString *field in @[@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY"])
        assert([restored[field] isEqual:rawWait[field]]);
    NSBitmapImageRep *output = [NSBitmapImageRep imageRepWithData:restored[@"Representations"][0]];
    assert(output.pixelsHigh == compatibleWaitFrames && output.pixelsWide == 2);
    for (NSInteger frame = 0; frame < compatibleWaitFrames; frame++) {
        NSUInteger pixel[4];
        [output getPixel:pixel atX:0 y:frame];
        assert(pixel[0] == (NSUInteger)frame * 16);
    }
    assert([readCape(path, YES)[waitCursor] isEqual:rawWait]);
    assert(restorableCursors(@{waitCursor: stockWait})[waitCursor] == stockWait);
}

int main(void) {
    @autoreleasepool {
        NSDictionary *original = nativeDefaults();
        NSMutableDictionary *legacy = [original mutableCopy];
        for (NSString *old in aliases()) {
            NSString *alias = aliases()[old];
            if (legacy[alias]) { legacy[old] = legacy[alias]; [legacy removeObjectForKey:alias]; }
        }
        NSDictionary *modern = effectiveCursors(legacy, YES);
        assert(modern.count == 4);
        assert(!modern[@"com.apple.coregraphics.Arrow"]);
        assert(!modern[@"com.apple.coregraphics.IBeam"]);
        assert([modern[@"com.apple.coregraphics.ArrowS"] isEqual:legacy[@"com.apple.coregraphics.Arrow"]]);
        assert([modern[@"com.apple.coregraphics.IBeamS"] isEqual:legacy[@"com.apple.coregraphics.IBeam"]]);
        assert([effectiveCursors(legacy, NO) isEqual:legacy]);
        assert([effectiveCursors(modern, YES) isEqual:modern]);
        NSMutableDictionary *explicitAlias = [legacy mutableCopy];
        explicitAlias[@"com.apple.coregraphics.ArrowS"] = @{@"custom": @YES};
        assert([effectiveCursors(explicitAlias, YES)[@"com.apple.coregraphics.ArrowS"] isEqual:explicitAlias[@"com.apple.coregraphics.ArrowS"]]);

        NSDictionary *wait = modern[@"com.apple.coregraphics.Wait"];
        NSMutableDictionary *observed = [wait mutableCopy];
        observed[@"FrameDuration"] = @([wait[@"FrameDuration"] doubleValue] + 0.00000001);
        assert(metadataMatches(wait, observed));
        for (NSString *field in @[@"PointsWide", @"PointsHigh", @"HotSpotX", @"HotSpotY", @"FrameCount", @"FrameDuration"]) {
            observed = [wait mutableCopy];
            observed[field] = @([wait[field] doubleValue] + 1);
            assert(!metadataMatches(wait, observed));
        }
        assert(!metadataMatches(wait, @{}));
        // Backup uses actual aliases and is accepted without changing any live cursor.
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"Cursors": modern}
            format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
        assert([data writeToFile:path atomically:YES]);
        assert([readCape(path, NO) isEqual:modern]);
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
        NSString *backup = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSError *error = nil;
        assert(saveBackup(legacy, backup, NO, &error));
        assert(!saveBackup(modern, backup, NO, &error));
        assert([readCape(backup, YES) isEqual:legacy]);
        assert(saveBackup(modern, backup, YES, &error));
        assert([readCape(backup, YES) isEqual:modern]);
        assert(saveBackup(@{@"com.apple.coregraphics.Wait": wait}, backup, YES, &error));
        assert(readCape(backup, YES).count == 1);
        testNativeWaitBackup(backup, wait);
        [NSFileManager.defaultManager removeItemAtPath:backup error:NULL];
        puts("PASS: aliases, backup round-trip, 30-frame native Wait recovery, and readback mismatch detection. No system cursor calls.");
    }
    return 0;
}
