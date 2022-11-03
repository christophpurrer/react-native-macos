/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RCTSurfaceTouchHandler.h"

#import <React/RCTUtils.h>
#import <React/RCTViewComponentView.h>

#import "RCTConversions.h"
#import "RCTTouchableComponentViewProtocol.h"

using namespace facebook::react;

template <size_t size>
class IdentifierPool {
 public:
  void enqueue(int index)
  {
    usage[index] = false;
  }

  int dequeue()
  {
    while (true) {
      if (!usage[lastIndex]) {
        usage[lastIndex] = true;
        return lastIndex;
      }
      lastIndex = (lastIndex + 1) % size;
    }
  }

  void reset()
  {
    for (int i = 0; i < size; i++) {
      usage[i] = false;
    }
  }

 private:
  bool usage[size];
  int lastIndex;
};

typedef NS_ENUM(NSInteger, RCTTouchEventType) {
  RCTTouchEventTypeTouchStart,
  RCTTouchEventTypeTouchMove,
  RCTTouchEventTypeTouchEnd,
  RCTTouchEventTypeTouchCancel,
};

struct ActiveTouch {
  Touch touch;
  SharedTouchEventEmitter eventEmitter;

  /*
   * A component view on which the touch was begun.
   */
  __strong RCTUIView<RCTComponentViewProtocol> *componentView = nil;

  struct Hasher {
    size_t operator()(const ActiveTouch &activeTouch) const
    {
      return std::hash<decltype(activeTouch.touch.identifier)>()(activeTouch.touch.identifier);
    }
  };

  struct Comparator {
    bool operator()(const ActiveTouch &lhs, const ActiveTouch &rhs) const
    {
      return lhs.touch.identifier == rhs.touch.identifier;
    }
  };
};

static void UpdateActiveTouchWithUITouch(
    ActiveTouch &activeTouch,
    RCTUITouch *uiTouch,
    RCTUIView *rootComponentView,
    CGPoint rootViewOriginOffset)
{
#if !TARGET_OS_OSX // TODO(macOS GH#774)
  CGPoint offsetPoint = [uiTouch locationInView:activeTouch.componentView];
  CGPoint screenPoint = [uiTouch locationInView:uiTouch.window];
  CGPoint pagePoint = [uiTouch locationInView:rootComponentView];
#else
  CGPoint offsetPoint = [activeTouch.componentView convertPoint:uiTouch.locationInWindow fromView:nil];
  CGPoint screenPoint = uiTouch.locationInWindow;
  CGPoint pagePoint = CGPointMake(screenPoint.x, CGRectGetHeight(rootComponentView.window.frame) - screenPoint.y);
#endif
  pagePoint = CGPointMake(pagePoint.x + rootViewOriginOffset.x, pagePoint.y + rootViewOriginOffset.y);

  activeTouch.touch.offsetPoint = RCTPointFromCGPoint(offsetPoint);
  activeTouch.touch.screenPoint = RCTPointFromCGPoint(screenPoint);
  activeTouch.touch.pagePoint = RCTPointFromCGPoint(pagePoint);

  activeTouch.touch.timestamp = uiTouch.timestamp;

#if !TARGET_OS_OSX // TODO(macOS GH#774)
  if (RCTForceTouchAvailable()) {
    activeTouch.touch.force = RCTZeroIfNaN(uiTouch.force / uiTouch.maximumPossibleForce);
  }
#endif
}

static ActiveTouch CreateTouchWithUITouch(RCTUITouch *uiTouch, RCTUIView *rootComponentView, CGPoint rootViewOriginOffset)
{
  ActiveTouch activeTouch = {};

  // Find closest Fabric-managed touchable view
#if !TARGET_OS_OSX // TODO(macOS GH#774)
  RCTUIView *componentView = uiTouch.view;
#else
  CGPoint touchLocation = [rootComponentView.superview convertPoint:uiTouch.locationInWindow fromView:nil];
  RCTUIView *componentView = (RCTUIView *) [rootComponentView hitTest:touchLocation];
#endif
  while (componentView) {
#if !TARGET_OS_OSX // TODO(macOS GH#774)
    CGPoint offsetPoint = [uiTouch locationInView:componentView];
#else
    CGPoint offsetPoint = [componentView convertPoint:uiTouch.locationInWindow fromView:nil];
#endif
    if ([componentView respondsToSelector:@selector(touchEventEmitterAtPoint:)]) {
      activeTouch.eventEmitter = [(id<RCTTouchableComponentViewProtocol>)componentView
          touchEventEmitterAtPoint:offsetPoint];
      activeTouch.touch.target = (Tag)componentView.tag;
      activeTouch.componentView = componentView;
      break;
    }
    componentView = (RCTUIView *) componentView.superview;
  }

  UpdateActiveTouchWithUITouch(activeTouch, uiTouch, rootComponentView, rootViewOriginOffset);
  return activeTouch;
}

#if !TARGET_OS_OSX // TODO(macOS GH#774)
static BOOL AllTouchesAreCancelledOrEnded(NSSet<RCTUITouch *> *touches)
{
  for (UITouch *touch in touches) {
    if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseStationary) {
      return NO;
    }
  }
  return YES;
}

static BOOL AnyTouchesChanged(NSSet<UITouch *> *touches)
{
  for (UITouch *touch in touches) {
    if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved) {
      return YES;
    }
  }
  return NO;
}
#endif // ]TODO(macOS GH#774)

/**
 * Surprisingly, `__unsafe_unretained id` pointers are not regular pointers
 * and `std::hash<>` cannot hash them.
 * This is quite trivial but decent implementation of hasher function
 * inspired by this research: https://stackoverflow.com/a/21062520/496389.
 */
template <typename PointerT>
struct PointerHasher {
  constexpr std::size_t operator()(const PointerT &value) const
  {
    return reinterpret_cast<size_t>(value);
  }
};

@interface RCTSurfaceTouchHandler () <UIGestureRecognizerDelegate>
@end

@implementation RCTSurfaceTouchHandler {
  std::unordered_map<__unsafe_unretained RCTUITouch *, ActiveTouch, PointerHasher<__unsafe_unretained RCTUITouch *>>
      _activeTouches;

  /*
   * We hold the view weakly to prevent a retain cycle.
   */
  __weak RCTUIView *_rootComponentView;
  IdentifierPool<11> _identifierPool;
}

- (instancetype)init
{
  if (self = [super initWithTarget:nil action:nil]) {
#if !TARGET_OS_OSX // TODO(macOS GH#774)
    // `cancelsTouchesInView` and `delaysTouches*` are needed in order
    // to be used as a top level event delegated recognizer.
    // Otherwise, lower-level components not built using React Native,
    // will fail to recognize gestures.
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO; // This is default value.
    self.delaysTouchesEnded = NO;
#else // [TODO(macOS GH#774)
    self.delaysPrimaryMouseButtonEvents = NO; // default is NO.
    self.delaysSecondaryMouseButtonEvents = NO; // default is NO.
    self.delaysOtherMouseButtonEvents = NO; // default is NO.
#endif // ]TODO(macOS GH#774)
      
    self.delegate = self;
  }

  return self;
}

RCT_NOT_IMPLEMENTED(-(instancetype)initWithTarget : (id)target action : (SEL)action)

- (void)attachToView:(RCTUIView *)view
{
  RCTAssert(self.view == nil, @"RCTTouchHandler already has attached view.");

  [view addGestureRecognizer:self];
  _rootComponentView = view;
}

- (void)detachFromView:(RCTUIView *)view
{
  RCTAssertParam(view);
  RCTAssert(self.view == view, @"RCTTouchHandler attached to another view.");

  [view removeGestureRecognizer:self];
  _rootComponentView = nil;
}

- (void)_registerTouches:(NSSet<RCTUITouch *> *)touches
{
  for (RCTUITouch *touch in touches) {
    auto activeTouch = CreateTouchWithUITouch(touch, _rootComponentView, _viewOriginOffset);
    activeTouch.touch.identifier = _identifierPool.dequeue();
    _activeTouches.emplace(touch, activeTouch);
  }
}

- (void)_updateTouches:(NSSet<RCTUITouch *> *)touches
{
  for (RCTUITouch *touch in touches) {
    auto iterator = _activeTouches.find(touch);
//    assert(iterator != _activeTouches.end() && "Inconsistency between local and UIKit touch registries");
    if (iterator == _activeTouches.end()) {
      continue;
    }

    UpdateActiveTouchWithUITouch(iterator->second, touch, _rootComponentView, _viewOriginOffset);
  }
}

- (void)_unregisterTouches:(NSSet<RCTUITouch *> *)touches
{
  for (RCTUITouch *touch in touches) {
    auto iterator = _activeTouches.find(touch);
//    assert(iterator != _activeTouches.end() && "Inconsistency between local and UIKit touch registries");
    if (iterator == _activeTouches.end()) {
      continue;
    }
    auto &activeTouch = iterator->second;
    _identifierPool.enqueue(activeTouch.touch.identifier);
    _activeTouches.erase(touch);
  }
}

- (std::vector<ActiveTouch>)_activeTouchesFromTouches:(NSSet<RCTUITouch *> *)touches
{
  std::vector<ActiveTouch> activeTouches;
  activeTouches.reserve(touches.count);

  for (RCTUITouch *touch in touches) {
    auto iterator = _activeTouches.find(touch);
//    assert(iterator != _activeTouches.end() && "Inconsistency between local and UIKit touch registries");
    if (iterator == _activeTouches.end()) {
      continue;
    }
    activeTouches.push_back(iterator->second);
  }

  return activeTouches;
}

- (void)_dispatchActiveTouches:(std::vector<ActiveTouch>)activeTouches eventType:(RCTTouchEventType)eventType
{
  TouchEvent event = {};
  std::unordered_set<ActiveTouch, ActiveTouch::Hasher, ActiveTouch::Comparator> changedActiveTouches = {};
  std::unordered_set<SharedTouchEventEmitter> uniqueEventEmitters = {};
  BOOL isEndishEventType = eventType == RCTTouchEventTypeTouchEnd || eventType == RCTTouchEventTypeTouchCancel;

  for (const auto &activeTouch : activeTouches) {
    if (!activeTouch.eventEmitter) {
      continue;
    }

    changedActiveTouches.insert(activeTouch);
    event.changedTouches.insert(activeTouch.touch);
    uniqueEventEmitters.insert(activeTouch.eventEmitter);
  }

  for (const auto &pair : _activeTouches) {
    if (!pair.second.eventEmitter) {
      continue;
    }

    if (isEndishEventType && event.changedTouches.find(pair.second.touch) != event.changedTouches.end()) {
      continue;
    }

    event.touches.insert(pair.second.touch);
  }

  for (const auto &eventEmitter : uniqueEventEmitters) {
    event.targetTouches.clear();

    for (const auto &pair : _activeTouches) {
      if (pair.second.eventEmitter == eventEmitter) {
        event.targetTouches.insert(pair.second.touch);
      }
    }

    switch (eventType) {
      case RCTTouchEventTypeTouchStart:
        eventEmitter->onTouchStart(event);
        break;
      case RCTTouchEventTypeTouchMove:
        eventEmitter->onTouchMove(event);
        break;
      case RCTTouchEventTypeTouchEnd:
        eventEmitter->onTouchEnd(event);
        break;
      case RCTTouchEventTypeTouchCancel:
        eventEmitter->onTouchCancel(event);
        break;
    }
  }
}

#pragma mark - `UIResponder`-ish touch-delivery methods

#if !TARGET_OS_OSX // [TODO(macOS GH#774)
- (void)touchesBegan:(NSSet<RCTUITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesBegan:touches withEvent:event];

  [self _registerTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchStart];

  if (self.state == UIGestureRecognizerStatePossible) {
    self.state = UIGestureRecognizerStateBegan;
  } else if (self.state == UIGestureRecognizerStateBegan) {
    self.state = UIGestureRecognizerStateChanged;
  }
}

- (void)touchesMoved:(NSSet<RCTUITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesMoved:touches withEvent:event];

  [self _updateTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchMove];

  self.state = UIGestureRecognizerStateChanged;
}

- (void)touchesEnded:(NSSet<RCTUITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesEnded:touches withEvent:event];

  [self _updateTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchEnd];
  [self _unregisterTouches:touches];

  if (AllTouchesAreCancelledOrEnded(event.allTouches)) {
    self.state = UIGestureRecognizerStateEnded;
  } else if (AnyTouchesChanged(event.allTouches)) {
    self.state = UIGestureRecognizerStateChanged;
  }
  self.state = UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet<RCTUITouch *> *)touches withEvent:(UIEvent *)event
{
  [super touchesCancelled:touches withEvent:event];

  [self _updateTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchCancel];
  [self _unregisterTouches:touches];

  if (AllTouchesAreCancelledOrEnded(event.allTouches)) {
    self.state = UIGestureRecognizerStateCancelled;
  } else if (AnyTouchesChanged(event.allTouches)) {
    self.state = UIGestureRecognizerStateChanged;
  }
}
#else

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  // This will only be called if the hit-tested view returns YES for acceptsFirstMouse,
  // therefore asking it again would be redundant.
  return YES;
}

- (void)mouseDown:(NSEvent *)event
{
  [super mouseDown:event];

    {
        // Filter out touches that were ignored.
        NSSet* touches = [NSSet setWithObject:event];
        touches = [touches objectsPassingTest:^(id touch, BOOL *stop) {
            //return [_nativeTouches containsObject:touch];
            return YES;
        }];
        
        [self _registerTouches:touches];
        [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchStart];
        
        if (self.state == UIGestureRecognizerStatePossible) {
            //    self.state = UIGestureRecognizerStateBegan;
        } else if (self.state == UIGestureRecognizerStateBegan) {
            //    self.state = UIGestureRecognizerStateChanged;
        }
    }
    
//    {
//        NSEvent *newEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
//                                               location:[event locationInWindow]
//                                          modifierFlags:[event modifierFlags]
//                                              timestamp:[event timestamp]
//                                           windowNumber:[event windowNumber]
//                                                context:nil
//                                            eventNumber:[event eventNumber]
//                                             clickCount:[event clickCount]
//                                               pressure:[event pressure]];
//
//        NSSet* touches = [NSSet setWithObject:event];
//        [self _updateTouches:touches];
//        [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchEnd];
//        [self _unregisterTouches:touches];
//    }
}
  
- (void)rightMouseDown:(NSEvent *)event
{
  [super rightMouseDown:event];
//  [self interactionsBegan:[NSSet setWithObject:event]];
}
  
- (void)mouseDragged:(NSEvent *)event
{
  [super mouseDragged:event];
    
  NSSet* touches = [NSSet setWithObject:event];
  [self _updateTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchMove];

//  self.state = UIGestureRecognizerStateChanged;
}
  
- (void)rightMouseDragged:(NSEvent *)event
{
  [super rightMouseDragged:event];
//  [self interactionsMoved:[NSSet setWithObject:event]];
}

- (void)mouseUp:(NSEvent *)event
{
  [super mouseUp:event];
    
  NSSet* touches = [NSSet setWithObject:event];
  [self _updateTouches:touches];
  [self _dispatchActiveTouches:[self _activeTouchesFromTouches:touches] eventType:RCTTouchEventTypeTouchEnd];
  [self _unregisterTouches:touches];

  // self.state = UIGestureRecognizerStateEnded;
}
  
- (void)rightMouseUp:(NSEvent *)event
{
  [super rightMouseUp:event];
//  [self interactionsEnded:[NSSet setWithObject:event] withEvent:event];
}

#endif

- (void)reset
{
  [super reset];

  if (!_activeTouches.empty()) {
    std::vector<ActiveTouch> activeTouches;
    activeTouches.reserve(_activeTouches.size());

    for (auto const &pair : _activeTouches) {
      activeTouches.push_back(pair.second);
    }

    [self _dispatchActiveTouches:activeTouches eventType:RCTTouchEventTypeTouchCancel];

    // Force-unregistering all the touches.
    _activeTouches.clear();
    _identifierPool.reset();
  }
}

- (BOOL)canPreventGestureRecognizer:(__unused UIGestureRecognizer *)preventedGestureRecognizer
{
  return NO;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer
{
  // We fail in favour of other external gesture recognizers.
  // iOS will ask `delegate`'s opinion about this gesture recognizer little bit later.
  return !RCTUIViewIsDescendantOfView(preventingGestureRecognizer.view, self.view); // TODO(macOS GH#774)
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gestureRecognizer
    shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  // Same condition for `failure of` as for `be prevented by`.
  return [self canBePreventedByGestureRecognizer:otherGestureRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  BOOL canBePrevented = [self canBePreventedByGestureRecognizer:otherGestureRecognizer];
  if (canBePrevented) {
    [self _cancelTouches];
  }
  return NO;
}

#pragma mark -

- (void)_cancelTouches
{
  [self setEnabled:NO];
  [self setEnabled:YES];
}

@end

// @generated SignedSource<<48743a61532d84c91ba63efa1e5ac419>>
