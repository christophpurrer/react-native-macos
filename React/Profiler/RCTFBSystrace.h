// (c) Facebook, Inc. and its affiliates. Confidential and proprietary.

#import <Foundation/Foundation.h>

@interface RCTFBSystrace : NSObject

+ (void)registerCallbacks;
+ (void)unregisterCallbacks;
+ (BOOL)verifyTraceSize:(size_t)size;

@end
