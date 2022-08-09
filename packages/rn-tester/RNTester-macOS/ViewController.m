//
//  ViewController.m
//  RNTester-macOS
//
//  Created by Jeff Cruikshank on 6/5/17.
//  Copyright © 2017 Facebook. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"

#import <React/RCTRootView.h>

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  RCTBridge *bridge = ((AppDelegate *)[NSApp delegate]).bridge;
  RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:bridge moduleName:kBundleNameJS initialProperties:nil];
  [self.view addSubview:rootView];
   
  // Taken from https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/ProgrammaticallyCreatingConstraints.html
  // Pin the leading edge of myView to the margin's leading edge
  [rootView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
   
  // Pin the trailing edge of myView to the margin's trailing edge
  [rootView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
   
  // Give myView a 1:2 aspect ratio
  [rootView.heightAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:2.0].active = YES;
    
  rootView.backgroundColor = [NSColor windowBackgroundColor];
  rootView.frame = self.view.bounds;
  rootView.autoresizingMask =
      (NSViewMinXMargin | NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin | NSViewWidthSizable |
       NSViewHeightSizable);
}

@end
