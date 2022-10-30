/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // TODO(macOS GH#774)

#import <React/RCTBackedTextInputViewProtocol.h>
#import <butter/optional.h>
#import <react/renderer/components/iostextinput/primitives.h>

NS_ASSUME_NONNULL_BEGIN

void RCTCopyBackedTextInput(
    RCTUIView<RCTBackedTextInputViewProtocol> *fromTextInput,
    RCTUIView<RCTBackedTextInputViewProtocol> *toTextInput);

NSInteger RCTUITextAutocorrectionTypeFromOptionalBool(facebook::butter::optional<bool> autoCorrect);

NSInteger RCTUITextAutocapitalizationTypeFromAutocapitalizationType(
    facebook::react::AutocapitalizationType autocapitalizationType);

NSInteger RCTUIKeyboardAppearanceFromKeyboardAppearance(
    facebook::react::KeyboardAppearance keyboardAppearance);

NSInteger RCTUITextSpellCheckingTypeFromOptionalBool(facebook::butter::optional<bool> spellCheck);

NSInteger RCTUITextFieldViewModeFromTextInputAccessoryVisibilityMode(
    facebook::react::TextInputAccessoryVisibilityMode mode);

NSInteger RCTUIKeyboardTypeFromKeyboardType(facebook::react::KeyboardType keyboardType);

NSInteger RCTUIReturnKeyTypeFromReturnKeyType(facebook::react::ReturnKeyType returnKeyType);

API_AVAILABLE(ios(10.0))
NSInteger RCTUITextContentTypeFromString(std::string const &contentType);

API_AVAILABLE(ios(12.0))
NSInteger *RCTUITextInputPasswordRulesFromString(std::string const &passwordRules);

NS_ASSUME_NONNULL_END
