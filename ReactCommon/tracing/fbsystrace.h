// (c) Facebook, Inc. and its affiliates. Confidential and proprietary.

#pragma once

#include <string>
#include <type_traits>

#define TRACE_TAG_REACT_CXX_BRIDGE 1 << 10
#define TRACE_TAG_REACT_APPS 1 << 11
#define SYSTRACE_SECTION_MAX_ARGS 8

// ARCHON_TRACING: This is a stub for xplat/fbsystrace/fbsystrace.h that allows us to
// implement systracing with minimal overhead in RN when not enabled so we can ship
// it in prod and enable it when needed for Loom tracing.

// The details will be implemented by the app/platform so it can log to Loom as
// well as system native tracing, e.g. ETW on Windows, Instruments for Mac etc.
namespace fbsystrace {
namespace detail {
// We rely on quickly being able to check this flag to eliminate the overhead in prod.
// The virtual call overhead is only incurred when tracing and is trivial compared the
// actual cost of tracing.
alignas(64) inline size_t trace_enabled = 0;
struct FbSystracer {
  static inline FbSystracer* tracer = nullptr;
  virtual bool begin_section(
      uint64_t tag,
      const char* name,
      const char* file,
      size_t line,
      const char** args,
      size_t argc) = 0;
  virtual void end_section() = 0;
  virtual bool begin_async_flow(uint64_t tag, const char* name, int callId) = 0;
  virtual void end_async_flow(uint64_t tag, const char* name, int callId) = 0;
};
} // namespace detail
} // namespace fbsystrace

inline void
fbsystrace_end_async_flow(uint64_t tag, const char* name, int callId) {
  if (fbsystrace::detail::trace_enabled) {
    fbsystrace::detail::FbSystracer::tracer->end_async_flow(tag, name, callId);
  }
}

namespace fbsystrace {

// These template helpers allow us to identify the file name part of the file
// path returned by __FILE__ at compile time with no runtime overhead.
constexpr const char* past_last_slash(
    const char* const str,
    const char* const last_slash) {
  return *str == '\0'                 ? last_slash
      : (*str == '/' || *str == '\\') ? past_last_slash(str + 1, str + 1)
                                      : past_last_slash(str + 1, last_slash);
}

constexpr const char* past_last_slash(const char* const str) {
  return past_last_slash(str, str);
}

// The source file/line are used as keys to throttle specific event sites in
// case they are logging too frequently, which may be why we want to trace in
// the first place. If we cannot throttle effectively the trace would either
// become too big or too short.
template <const char FBFILEPATH[], size_t FBLINE = 0>
class FbSystraceSection {
  // Determine the file name - it is shorter and typically matches class name
  static constexpr const char* const FBFILENAME = {past_last_slash(FBFILEPATH)};
  static const uint64_t TAG = TRACE_TAG_REACT_CXX_BRIDGE;

 public:
  FbSystraceSection(
      const char* profileName,
      const char* arg1,
      const std::string& val1) {
    if (detail::trace_enabled) {
      const char* args[] = {arg1, val1.c_str()};
      started_ = detail::FbSystracer::tracer->begin_section(
          TAG, profileName, FBFILENAME, FBLINE, args, 2);
    }
  }
  FbSystraceSection(
      const char* profileName,
      const char* arg1,
      const std::string& val1,
      const char* arg2,
      const std::string& val2) {
    if (detail::trace_enabled) {
      const char* args[] = {arg1, val1.c_str(), arg2, val2.c_str()};
      started_ = detail::FbSystracer::tracer->begin_section(
          TAG, profileName, FBFILENAME, FBLINE, args, 4);
    }
  }

  // Currently we opt for efficiency and unless we have an efficient override
  // we'll not pick up the parameters.
  template <typename... RestArg>
  FbSystraceSection(const char* profileName, RestArg&&...) {
    if (detail::trace_enabled) {
      started_ = detail::FbSystracer::tracer->begin_section(
          TAG, profileName, FBFILENAME, FBLINE, nullptr, 0);
    }
  }

  ~FbSystraceSection() {
    if (detail::trace_enabled && started_) {
      detail::FbSystracer::tracer->end_section();
    }
  }

  bool started_ = false;
};

struct FbSystraceAsyncFlow {
  static bool begin(uint64_t tag, const char* name, int cookie) {
    if (detail::trace_enabled) {
      return detail::FbSystracer::tracer->begin_async_flow(tag, name, cookie);
    }
    return false;
  }

  static void end(uint64_t tag, const char* name, int cookie) {
    if (detail::trace_enabled) {
      detail::FbSystracer::tracer->end_async_flow(tag, name, cookie);
    }
  }
};
} // namespace fbsystrace

// @generated SignedSource<<64ef8ae3eeef623122595efbde113325>>
