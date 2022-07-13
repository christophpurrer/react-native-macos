/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <react/renderer/components/view/ViewProps.h>
#include <react/renderer/graphics/Transform.h>

namespace facebook {
namespace react {

/**
 * Given animation progress, old props, new props, and an "interpolated" shared
 * props struct, this will mutate the "interpolated" struct in-place to give it
 * values interpolated between the old and new props.
 */
static inline void interpolateViewProps(
    Float animationProgress,
    const Props::Shared &oldPropsShared,
    const Props::Shared &newPropsShared,
    Props::Shared &interpolatedPropsShared) {
  ViewProps const *oldViewProps =
      static_cast<ViewProps const *>(oldPropsShared.get());
  ViewProps const *newViewProps =
      static_cast<ViewProps const *>(newPropsShared.get());
  ViewProps *interpolatedProps = const_cast<ViewProps *>(
      static_cast<ViewProps const *>(interpolatedPropsShared.get()));

  interpolatedProps->opacity = oldViewProps->opacity +
      (newViewProps->opacity - oldViewProps->opacity) * animationProgress;

  interpolatedProps->transform = Transform::Interpolate(
      animationProgress, oldViewProps->transform, newViewProps->transform);

  // Android uses RawProps, not props, to update props on the platform...
  // Since interpolated props don't interpolate at all using RawProps, we need
  // to "re-hydrate" raw props after interpolating. This is what actually gets
  // sent to the mounting layer. This is a temporary hack, only for platforms
  // that use RawProps/folly::dynamic instead of concrete props on the
  // mounting layer. Once we can remove this, we should change `rawProps` to
  // be const again.
#ifdef ANDROID
  interpolatedProps->rawProps["opacity"] = interpolatedProps->opacity;

  interpolatedProps->rawProps["transform"] =
      (folly::dynamic)interpolatedProps->transform;
#endif
}

} // namespace react
} // namespace facebook
