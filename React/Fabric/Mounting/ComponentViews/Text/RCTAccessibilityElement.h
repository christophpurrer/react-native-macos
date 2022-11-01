/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // TODO(macOS GH#774)

NS_ASSUME_NONNULL_BEGIN

#if !TARGET_OS_OSX // TODO(macOS GH#774)
@interface RCTAccessibilityElement : UIAccessibilityElement
#else
@interface RCTAccessibilityElement : NSAccessibilityElement
#endif

/*
 * Frame of the accessibility element in parent coordinate system.
 * Set to `CGRectZero` to use size of the container.
 *
 * Default value: `CGRectZero`.
 */
#if !TARGET_OS_OSX // TODO(macOS GH#774)
@property (nonatomic, assign) CGRect frame;
#endif
@end

NS_ASSUME_NONNULL_END
