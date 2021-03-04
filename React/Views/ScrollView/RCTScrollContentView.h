/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // TODO(macOS GH#774)

#import <React/RCTView.h>

@interface RCTScrollContentView : RCTView

#if TARGET_OS_OSX // [TODO(macOS ISS#2323203)
@property (nonatomic, assign, getter=isInverted) BOOL inverted;
#endif // ]TODO(macOS ISS#2323203)

@end
