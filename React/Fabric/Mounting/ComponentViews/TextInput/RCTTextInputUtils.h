/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // TODO(macOS GH#774)

#import <optional>

#import <React/RCTBackedTextInputViewProtocol.h>
#import <React/RCTUITextField.h>
#import <React/RCTUITextView.h>
#import <react/renderer/components/iostextinput/primitives.h>

NS_ASSUME_NONNULL_BEGIN

void RCTCopyBackedTextInput(
#if !TARGET_OS_OSX // TODO(macOS GH#774)
    RCTUIView<RCTBackedTextInputViewProtocol> *fromTextInput,
    RCTUIView<RCTBackedTextInputViewProtocol> *toTextInput
#else
    RCTUITextView<RCTBackedTextInputViewProtocol> *fromTextInput,
    RCTUITextView<RCTBackedTextInputViewProtocol> *toTextInput
#endif
);

#if !TARGET_OS_OSX // TODO(macOS GH#774)
UITextAutocorrectionType RCTUITextAutocorrectionTypeFromOptionalBool(std::optional<bool> autoCorrect);

UITextAutocapitalizationType RCTUITextAutocapitalizationTypeFromAutocapitalizationType(
    facebook::react::AutocapitalizationType autocapitalizationType);

UIKeyboardAppearance RCTUIKeyboardAppearanceFromKeyboardAppearance(
    facebook::react::KeyboardAppearance keyboardAppearance);

UITextSpellCheckingType RCTUITextSpellCheckingTypeFromOptionalBool(std::optional<bool> spellCheck);

UITextFieldViewMode RCTUITextFieldViewModeFromTextInputAccessoryVisibilityMode(
    facebook::react::TextInputAccessoryVisibilityMode mode);

UIKeyboardType RCTUIKeyboardTypeFromKeyboardType(facebook::react::KeyboardType keyboardType);

UIReturnKeyType RCTUIReturnKeyTypeFromReturnKeyType(facebook::react::ReturnKeyType returnKeyType);

API_AVAILABLE(ios(10.0))
UITextContentType RCTUITextContentTypeFromString(std::string const &contentType);

API_AVAILABLE(ios(12.0))
UITextInputPasswordRules *RCTUITextInputPasswordRulesFromString(std::string const &passwordRules);
#endif

NS_ASSUME_NONNULL_END
