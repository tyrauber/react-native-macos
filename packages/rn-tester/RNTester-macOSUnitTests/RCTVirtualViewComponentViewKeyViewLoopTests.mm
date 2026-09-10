/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <React/RCTVirtualViewComponentView.h>

/*
 * RCTVirtualViewComponentView hides itself (`self.hidden = YES`) when it
 * scrolls off screen. It then unhides itself lazily, the first time something
 * asks it a question that only a visible view can answer.
 *
 * On macOS the automatic key view loop (Tab order) asks `-canBecomeKeyView`,
 * and NSView's default implementation answers NO for a hidden view without
 * ever calling `-acceptsFirstResponder`. Without a `-canBecomeKeyView`
 * override, a hidden VirtualView and everything inside it is permanently
 * unreachable by Tab.
 *
 * These tests build a real NSWindow, ask AppKit to build the real automatic
 * key view loop, and then read that loop with `-nextValidKeyView` — the exact
 * query AppKit runs to decide where a Tab press sends focus.
 *
 * KNOWN LIMIT OF THIS TEST TARGET: RNTester-macOSUnitTests has no TEST_HOST,
 * so it runs inside the `xctest` command line tool rather than a real app.
 * That process never activates, so `-[NSWindow makeKeyAndOrderFront:]` leaves
 * `isKeyWindow` NO and `-[NSWindow selectNextKeyView:]` does not move the
 * first responder — this was measured, with plain NSTextFields in a plain
 * NSView, and it fails there too. The key view loop itself is built correctly
 * in this environment, so these tests assert on the loop rather than on the
 * first responder. Moving focus for real needs a hosted (app) test bundle.
 */
@interface RCTVirtualViewComponentViewKeyViewLoopTests : XCTestCase
@end

@implementation RCTVirtualViewComponentViewKeyViewLoopTests {
  NSWindow *_window;
  NSTextField *_anchorField;
  RCTVirtualViewComponentView *_virtualView;
  NSTextField *_innerField;
}

- (void)setUp
{
  [super setUp];

  // Make sure NSApp exists before any window is created.
  [NSApplication sharedApplication];

  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 400)
                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                        NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  _window.releasedWhenClosed = NO;

  NSView *contentView = _window.contentView;

  // An always-focusable field above the VirtualView. Tab order starts here.
  // NSTextField is used rather than NSButton because buttons only join the key
  // view loop when "Full Keyboard Access" is enabled system wide, which would
  // make this test depend on a machine setting.
  _anchorField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 340, 200, 24)];
  [contentView addSubview:_anchorField];

  _virtualView = [[RCTVirtualViewComponentView alloc] initWithFrame:NSMakeRect(20, 100, 200, 100)];

  _innerField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 40, 200, 24)];
  [_virtualView addSubview:_innerField];

  [contentView addSubview:_virtualView];
}

- (void)tearDown
{
  [_window close];
  _window = nil;
  _anchorField = nil;
  _virtualView = nil;
  _innerField = nil;

  [super tearDown];
}

- (NSString *)_environmentDescription
{
  return [NSString stringWithFormat:@"NSApp.isActive=%@ window.isKeyWindow=%@ virtualView.hidden=%@",
                                    NSApp.isActive ? @"YES" : @"NO",
                                    _window.isKeyWindow ? @"YES" : @"NO",
                                    _virtualView.isHidden ? @"YES" : @"NO"];
}

/*
 * The mechanism, in isolation: asking a hidden VirtualView whether it can
 * become a key view unhides it as a side effect.
 */
- (void)testCanBecomeKeyViewUnhidesHiddenVirtualView
{
  _virtualView.hidden = YES;
  XCTAssertTrue(_virtualView.isHidden);

  (void)[_virtualView canBecomeKeyView];

  XCTAssertFalse(
      _virtualView.isHidden, @"-canBecomeKeyView must unhide a hidden VirtualView so Tab navigation can reach it.");
}

/*
 * End to end: AppKit's own key view loop machinery visits a hidden VirtualView
 * and unhides it. Nothing in this test touches the VirtualView directly.
 */
- (void)testKeyViewLoopTraversalUnhidesHiddenVirtualView
{
  _virtualView.hidden = YES;

  [_window makeKeyAndOrderFront:nil];
  [_window recalculateKeyViewLoop];
  [_window selectNextKeyView:nil];

  XCTAssertFalse(
      _virtualView.isHidden,
      @"AppKit's key view loop must unhide the VirtualView while walking Tab order. %@",
      [self _environmentDescription]);
}

/*
 * The part that matters to a keyboard user: after the key view loop is built,
 * the field inside the previously hidden VirtualView is the next stop in Tab
 * order. `-nextValidKeyView` is the query AppKit runs on a Tab press to pick
 * that view.
 */
- (void)testKeyViewLoopReachesFocusableContentInsideHiddenVirtualView
{
  _virtualView.hidden = YES;

  // Control: while the container is hidden, its focusable child is not a
  // candidate for Tab. This is the state the fix has to break out of. Reading
  // the child, not the container, so nothing is unhidden by asking.
  XCTAssertFalse(
      _innerField.canBecomeKeyView,
      @"Precondition: a field inside a hidden container must start out unreachable by Tab.");

  [_window makeKeyAndOrderFront:nil];
  [_window recalculateKeyViewLoop];

  XCTAssertEqualObjects(
      _anchorField.nextValidKeyView,
      _innerField,
      @"Tab order must reach the field inside the previously hidden VirtualView. %@",
      [self _environmentDescription]);
}

@end
