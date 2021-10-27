// (c) Facebook, Inc. and its affiliates. Confidential and proprietary.

#import "RCTFBSystrace.h"
#import "RCTProfile.h"

#ifdef WITH_FBSYSTRACE
#include <fbsystrace.h>
#endif

// ARCHON_TRACING: Dummy implementation for RCTFBSystrace required to build with WITH_FBSYSTRACE
@implementation RCTFBSystrace

+ (void)registerCallbacks
{
}

+ (void)unregisterCallbacks
{
}

+ (BOOL)verifyTraceSize:(size_t)size
{
  return YES;
}

@end

// ARCHON_TRACING: Routines to forward existing RCTProfile tracing to Loom
#ifdef WITH_FBSYSTRACE
RCT_EXTERN BOOL _RCTLoomIsProfiling(void) {
  return fbsystrace::detail::trace_enabled;
}

RCT_EXTERN BOOL _RCTLoomBeginEvent(
    NSString *name,
    const char *file,
    size_t line,
    NSDictionary<NSString *, NSString *> *args) {
  const char* strArgsBuffer[8] = {};
  const size_t argcMax = std::size(strArgsBuffer);
  const char** strArgs = strArgsBuffer;
  __block size_t argc = 0;
  [args enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
    if (argc + 1 < argcMax) {
      strArgs[argc++] = [key UTF8String];
      strArgs[argc++] = [value UTF8String];
    }
  }];
  return fbsystrace::detail::FbSystracer::tracer->begin_section(TRACE_TAG_REACT_APPS, [name UTF8String], fbsystrace::past_last_slash(file), line, strArgs, argc);
}

RCT_EXTERN void _RCTLoomEndEvent() {
  fbsystrace::detail::FbSystracer::tracer->end_section();
}
#endif

// @generated SignedSource<<c75c9a59e9845b29a47ff010ba3e8d3b>>
