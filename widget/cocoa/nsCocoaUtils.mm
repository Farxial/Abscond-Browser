/* -*- Mode: C++; tab-width: 20; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "gfxImageSurface.h"
#include "nsCocoaUtils.h"
#include "nsChildView.h"
#include "nsMenuBarX.h"
#include "nsCocoaWindow.h"
#include "nsCOMPtr.h"
#include "nsIInterfaceRequestorUtils.h"
#include "nsIAppShellService.h"
#include "nsIXULWindow.h"
#include "nsIBaseWindow.h"
#include "nsIServiceManager.h"
#include "nsMenuUtilsX.h"
#include "nsToolkit.h"
#include "nsGUIEvent.h"
#include "mozilla/Preferences.h"

using namespace mozilla;
using namespace mozilla::widget;

static float
MenuBarScreenHeight()
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_RETURN;

  NSArray* allScreens = [NSScreen screens];
  if ([allScreens count]) {
    return [[allScreens objectAtIndex:0] frame].size.height;
  }

  return 0.0;

  NS_OBJC_END_TRY_ABORT_BLOCK_RETURN(0.0);
}

float
nsCocoaUtils::FlippedScreenY(float y)
{
  return MenuBarScreenHeight() - y;
}

NSRect nsCocoaUtils::GeckoRectToCocoaRect(const nsIntRect &geckoRect)
{
  // We only need to change the Y coordinate by starting with the primary screen
  // height and subtracting the gecko Y coordinate of the bottom of the rect.
  return NSMakeRect(geckoRect.x,
                    MenuBarScreenHeight() - geckoRect.YMost(),
                    geckoRect.width,
                    geckoRect.height);
}

NSRect nsCocoaUtils::GeckoRectToCocoaRectDevPix(const nsIntRect &aGeckoRect,
                                                CGFloat aBackingScale)
{
  return NSMakeRect(aGeckoRect.x / aBackingScale,
                    MenuBarScreenHeight() - aGeckoRect.YMost() / aBackingScale,
                    aGeckoRect.width / aBackingScale,
                    aGeckoRect.height / aBackingScale);
}

nsIntRect nsCocoaUtils::CocoaRectToGeckoRect(const NSRect &cocoaRect)
{
  // We only need to change the Y coordinate by starting with the primary screen
  // height and subtracting both the cocoa y origin and the height of the
  // cocoa rect.
  nsIntRect rect;
  rect.x = NSToIntRound(cocoaRect.origin.x);
  rect.y = NSToIntRound(FlippedScreenY(cocoaRect.origin.y + cocoaRect.size.height));
  rect.width = NSToIntRound(cocoaRect.origin.x + cocoaRect.size.width) - rect.x;
  rect.height = NSToIntRound(FlippedScreenY(cocoaRect.origin.y)) - rect.y;
  return rect;
}

nsIntRect nsCocoaUtils::CocoaRectToGeckoRectDevPix(const NSRect &aCocoaRect,
                                                   CGFloat aBackingScale)
{
  nsIntRect rect;
  rect.x = NSToIntRound(aCocoaRect.origin.x * aBackingScale);
  rect.y = NSToIntRound(FlippedScreenY(aCocoaRect.origin.y + aCocoaRect.size.height) * aBackingScale);
  rect.width = NSToIntRound((aCocoaRect.origin.x + aCocoaRect.size.width) * aBackingScale) - rect.x;
  rect.height = NSToIntRound(FlippedScreenY(aCocoaRect.origin.y) * aBackingScale) - rect.y;
  return rect;
}

NSPoint nsCocoaUtils::ScreenLocationForEvent(NSEvent* anEvent)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_RETURN;

  // Don't trust mouse locations of mouse move events, see bug 443178.
  if (!anEvent || [anEvent type] == NSMouseMoved)
    return [NSEvent mouseLocation];

  // Pin momentum scroll events to the location of the last user-controlled
  // scroll event.
  if (IsMomentumScrollEvent(anEvent))
    return ChildViewMouseTracker::sLastScrollEventScreenLocation;

  return [[anEvent window] convertBaseToScreen:[anEvent locationInWindow]];

  NS_OBJC_END_TRY_ABORT_BLOCK_RETURN(NSMakePoint(0.0, 0.0));
}

BOOL nsCocoaUtils::IsEventOverWindow(NSEvent* anEvent, NSWindow* aWindow)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_RETURN;

  return NSPointInRect(ScreenLocationForEvent(anEvent), [aWindow frame]);

  NS_OBJC_END_TRY_ABORT_BLOCK_RETURN(NO);
}

NSPoint nsCocoaUtils::EventLocationForWindow(NSEvent* anEvent, NSWindow* aWindow)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_RETURN;

  return [aWindow convertScreenToBase:ScreenLocationForEvent(anEvent)];

  NS_OBJC_END_TRY_ABORT_BLOCK_RETURN(NSMakePoint(0.0, 0.0));
}

BOOL nsCocoaUtils::IsMomentumScrollEvent(NSEvent* aEvent)
{
  if ([aEvent type] != NSScrollWheel)
    return NO;
    
  if ([aEvent respondsToSelector:@selector(momentumPhase)])
    return ([aEvent momentumPhase] & NSEventPhaseChanged) != 0;
    
  if ([aEvent respondsToSelector:@selector(_scrollPhase)])
    return [aEvent _scrollPhase] != 0;
    
  return NO;
}

void nsCocoaUtils::HideOSChromeOnScreen(bool aShouldHide, NSScreen* aScreen)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  // Keep track of how many hiding requests have been made, so that they can
  // be nested.
  static int sMenuBarHiddenCount = 0, sDockHiddenCount = 0;

  // Always hide the Dock, since it's not necessarily on the primary screen.
  sDockHiddenCount += aShouldHide ? 1 : -1;
  NS_ASSERTION(sMenuBarHiddenCount >= 0, "Unbalanced HideMenuAndDockForWindow calls");

  // Only hide the menu bar if the window is on the same screen.
  // The menu bar is always on the first screen in the screen list.
  if (aScreen == [[NSScreen screens] objectAtIndex:0]) {
    sMenuBarHiddenCount += aShouldHide ? 1 : -1;
    NS_ASSERTION(sDockHiddenCount >= 0, "Unbalanced HideMenuAndDockForWindow calls");
  }

  // TODO This should be upgraded to use [NSApplication setPresentationOptions:]
  // when support for 10.5 is dropped.
  if (sMenuBarHiddenCount > 0) {
    ::SetSystemUIMode(kUIModeAllHidden, 0);
  } else if (sDockHiddenCount > 0) {
    ::SetSystemUIMode(kUIModeContentHidden, 0);
  } else {
    ::SetSystemUIMode(kUIModeNormal, 0);
  }

  NS_OBJC_END_TRY_ABORT_BLOCK;
}


#define NS_APPSHELLSERVICE_CONTRACTID "@mozilla.org/appshell/appShellService;1"
nsIWidget* nsCocoaUtils::GetHiddenWindowWidget()
{
  nsCOMPtr<nsIAppShellService> appShell(do_GetService(NS_APPSHELLSERVICE_CONTRACTID));
  if (!appShell) {
    NS_WARNING("Couldn't get AppShellService in order to get hidden window ref");
    return nullptr;
  }
  
  nsCOMPtr<nsIXULWindow> hiddenWindow;
  appShell->GetHiddenWindow(getter_AddRefs(hiddenWindow));
  if (!hiddenWindow) {
    // Don't warn, this happens during shutdown, bug 358607.
    return nullptr;
  }
  
  nsCOMPtr<nsIBaseWindow> baseHiddenWindow;
  baseHiddenWindow = do_GetInterface(hiddenWindow);
  if (!baseHiddenWindow) {
    NS_WARNING("Couldn't get nsIBaseWindow from hidden window (nsIXULWindow)");
    return nullptr;
  }
  
  nsCOMPtr<nsIWidget> hiddenWindowWidget;
  if (NS_FAILED(baseHiddenWindow->GetMainWidget(getter_AddRefs(hiddenWindowWidget)))) {
    NS_WARNING("Couldn't get nsIWidget from hidden window (nsIBaseWindow)");
    return nullptr;
  }
  
  return hiddenWindowWidget;
}

void nsCocoaUtils::PrepareForNativeAppModalDialog()
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  // Don't do anything if this is embedding. We'll assume that if there is no hidden
  // window we shouldn't do anything, and that should cover the embedding case.
  nsMenuBarX* hiddenWindowMenuBar = nsMenuUtilsX::GetHiddenWindowMenuBar();
  if (!hiddenWindowMenuBar)
    return;

  // First put up the hidden window menu bar so that app menu event handling is correct.
  hiddenWindowMenuBar->Paint();

  NSMenu* mainMenu = [NSApp mainMenu];
  NS_ASSERTION([mainMenu numberOfItems] > 0, "Main menu does not have any items, something is terribly wrong!");
  
  // Create new menu bar for use with modal dialog
  NSMenu* newMenuBar = [[NSMenu alloc] initWithTitle:@""];
  
  // Swap in our app menu. Note that the event target is whatever window is up when
  // the app modal dialog goes up.
  NSMenuItem* firstMenuItem = [[mainMenu itemAtIndex:0] retain];
  [mainMenu removeItemAtIndex:0];
  [newMenuBar insertItem:firstMenuItem atIndex:0];
  [firstMenuItem release];
  
  // Add standard edit menu
  [newMenuBar addItem:nsMenuUtilsX::GetStandardEditMenuItem()];
  
  // Show the new menu bar
  [NSApp setMainMenu:newMenuBar];
  [newMenuBar release];
  
  NS_OBJC_END_TRY_ABORT_BLOCK;
}

void nsCocoaUtils::CleanUpAfterNativeAppModalDialog()
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  // Don't do anything if this is embedding. We'll assume that if there is no hidden
  // window we shouldn't do anything, and that should cover the embedding case.
  nsMenuBarX* hiddenWindowMenuBar = nsMenuUtilsX::GetHiddenWindowMenuBar();
  if (!hiddenWindowMenuBar)
    return;

  NSWindow* mainWindow = [NSApp mainWindow];
  if (!mainWindow)
    hiddenWindowMenuBar->Paint();
  else
    [WindowDelegate paintMenubarForWindow:mainWindow];

  NS_OBJC_END_TRY_ABORT_BLOCK;
}

nsresult nsCocoaUtils::CreateCGImageFromSurface(gfxImageSurface *aFrame, CGImageRef *aResult)
{

  int32_t width = aFrame->Width();
  int32_t stride = aFrame->Stride();
  int32_t height = aFrame->Height();
  if ((stride % 4 != 0) || (height < 1) || (width < 1)) {
    return NS_ERROR_FAILURE;
  }

  // Create a CGImageRef with the bits from the image, taking into account
  // the alpha ordering and endianness of the machine so we don't have to
  // touch the bits ourselves.
  CGDataProviderRef dataProvider = ::CGDataProviderCreateWithData(NULL,
                                                                  aFrame->Data(),
                                                                  stride * height,
                                                                  NULL);
  CGColorSpaceRef colorSpace = ::CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
  *aResult = ::CGImageCreate(width,
                             height,
                             8,
                             32,
                             stride,
                             colorSpace,
                             kCGBitmapByteOrder32Host | kCGImageAlphaFirst,
                             dataProvider,
                             NULL,
                             0,
                             kCGRenderingIntentDefault);
  ::CGColorSpaceRelease(colorSpace);
  ::CGDataProviderRelease(dataProvider);
  return *aResult ? NS_OK : NS_ERROR_FAILURE;
}

nsresult nsCocoaUtils::CreateNSImageFromCGImage(CGImageRef aInputImage, NSImage **aResult)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NSRESULT;

  int32_t width = ::CGImageGetWidth(aInputImage);
  int32_t height = ::CGImageGetHeight(aInputImage);
  NSRect imageRect = ::NSMakeRect(0.0, 0.0, width, height);

  // Create a new image to receive the Quartz image data.
  *aResult = [[NSImage alloc] initWithSize:imageRect.size];

  [*aResult lockFocus];

  // Get the Quartz context and draw.
  CGContextRef imageContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
  ::CGContextDrawImage(imageContext, *(CGRect*)&imageRect, aInputImage);

  [*aResult unlockFocus];
  return NS_OK;

  NS_OBJC_END_TRY_ABORT_BLOCK_NSRESULT;
}

nsresult nsCocoaUtils::CreateNSImageFromImageContainer(imgIContainer *aImage, uint32_t aWhichFrame, NSImage **aResult)
{
  nsRefPtr<gfxASurface> surface;
  aImage->GetFrame(aWhichFrame,
                   imgIContainer::FLAG_SYNC_DECODE,
                   getter_AddRefs(surface));
  NS_ENSURE_TRUE(surface, NS_ERROR_FAILURE);

  nsRefPtr<gfxImageSurface> frame(surface->GetAsReadableARGB32ImageSurface());
  NS_ENSURE_TRUE(frame, NS_ERROR_FAILURE);

  CGImageRef imageRef = NULL;
  nsresult rv = nsCocoaUtils::CreateCGImageFromSurface(frame, &imageRef);
  if (NS_FAILED(rv) || !imageRef) {
    return NS_ERROR_FAILURE;
  }

  rv = nsCocoaUtils::CreateNSImageFromCGImage(imageRef, aResult);
  if (NS_FAILED(rv) || !aResult) {
    return NS_ERROR_FAILURE;
  }
  ::CGImageRelease(imageRef);
  return NS_OK;
}

// static
void
nsCocoaUtils::GetStringForNSString(const NSString *aSrc, nsAString& aDist)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  if (!aSrc) {
    aDist.Truncate();
    return;
  }

  aDist.SetLength([aSrc length]);
  [aSrc getCharacters: aDist.BeginWriting()];

  NS_OBJC_END_TRY_ABORT_BLOCK;
}

// static
NSString*
nsCocoaUtils::ToNSString(const nsAString& aString)
{
  return [NSString stringWithCharacters:aString.BeginReading()
                                 length:aString.Length()];
}

// static
void
nsCocoaUtils::GeckoRectToNSRect(const nsIntRect& aGeckoRect,
                                NSRect& aOutCocoaRect)
{
  aOutCocoaRect.origin.x = aGeckoRect.x;
  aOutCocoaRect.origin.y = aGeckoRect.y;
  aOutCocoaRect.size.width = aGeckoRect.width;
  aOutCocoaRect.size.height = aGeckoRect.height;
}

// static
void
nsCocoaUtils::NSRectToGeckoRect(const NSRect& aCocoaRect,
                                nsIntRect& aOutGeckoRect)
{
  aOutGeckoRect.x = NSToIntRound(aCocoaRect.origin.x);
  aOutGeckoRect.y = NSToIntRound(aCocoaRect.origin.y);
  aOutGeckoRect.width = NSToIntRound(aCocoaRect.origin.x + aCocoaRect.size.width) - aOutGeckoRect.x;
  aOutGeckoRect.height = NSToIntRound(aCocoaRect.origin.y + aCocoaRect.size.height) - aOutGeckoRect.y;
}

// static
NSEvent*
nsCocoaUtils::MakeNewCocoaEventWithType(NSEventType aEventType, NSEvent *aEvent)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK_NIL;

  NSEvent* newEvent =
    [NSEvent     keyEventWithType:aEventType
                         location:[aEvent locationInWindow] 
                    modifierFlags:[aEvent modifierFlags]
                        timestamp:[aEvent timestamp]
                     windowNumber:[aEvent windowNumber]
                          context:[aEvent context]
                       characters:[aEvent characters]
      charactersIgnoringModifiers:[aEvent charactersIgnoringModifiers]
                        isARepeat:[aEvent isARepeat]
                          keyCode:[aEvent keyCode]];
  return newEvent;

  NS_OBJC_END_TRY_ABORT_BLOCK_NIL;
}

// static
void
nsCocoaUtils::InitNPCocoaEvent(NPCocoaEvent* aNPCocoaEvent)
{
  memset(aNPCocoaEvent, 0, sizeof(NPCocoaEvent));
}

// static
void
nsCocoaUtils::InitPluginEvent(nsPluginEvent &aPluginEvent,
                              NPCocoaEvent &aCocoaEvent)
{
  aPluginEvent.time = PR_IntervalNow();
  aPluginEvent.pluginEvent = (void*)&aCocoaEvent;
  aPluginEvent.retargetToFocusedDocument = false;
}

// static
void
nsCocoaUtils::InitInputEvent(nsInputEvent &aInputEvent,
                             NSEvent* aNativeEvent)
{
  NS_OBJC_BEGIN_TRY_ABORT_BLOCK;

  NSUInteger modifiers =
    aNativeEvent ? [aNativeEvent modifierFlags] : [NSEvent modifierFlags];
  InitInputEvent(aInputEvent, modifiers);

  aInputEvent.time = PR_IntervalNow();

  NS_OBJC_END_TRY_ABORT_BLOCK;
}

// static
void
nsCocoaUtils::InitInputEvent(nsInputEvent &aInputEvent,
                             NSUInteger aModifiers)
{
  aInputEvent.modifiers = 0;
  if (aModifiers & NSShiftKeyMask) {
    aInputEvent.modifiers |= MODIFIER_SHIFT;
  }
  if (aModifiers & NSControlKeyMask) {
    aInputEvent.modifiers |= MODIFIER_CONTROL;
  }
  if (aModifiers & NSAlternateKeyMask) {
    aInputEvent.modifiers |= MODIFIER_ALT;
    // Mac's option key is similar to other platforms' AltGr key.
    // Let's set AltGr flag when option key is pressed for consistency with
    // other platforms.
    aInputEvent.modifiers |= MODIFIER_ALTGRAPH;
  }
  if (aModifiers & NSCommandKeyMask) {
    aInputEvent.modifiers |= MODIFIER_META;
  }

  if (aModifiers & NSAlphaShiftKeyMask) {
    aInputEvent.modifiers |= MODIFIER_CAPSLOCK;
  }
  // Mac doesn't have NumLock key.  We can assume that NumLock is always locked
  // if user is using a keyboard which has numpad.  Otherwise, if user is using
  // a keyboard which doesn't have numpad, e.g., MacBook's keyboard, we can
  // assume that NumLock is always unlocked.
  // Unfortunately, we cannot know whether current keyboard has numpad or not.
  // We should notify locked state only when keys in numpad are pressed.
  // By this, web applications may not be confused by unexpected numpad key's
  // key event with unlocked state.
  if (aModifiers & NSNumericPadKeyMask) {
    aInputEvent.modifiers |= MODIFIER_NUMLOCK;
  }

  // Be aware, NSFunctionKeyMask is included when arrow keys, home key or some
  // other keys are pressed. We cannot check whether 'fn' key is pressed or
  // not by the flag.

}

// static
UInt32
nsCocoaUtils::ConvertToCarbonModifier(NSUInteger aCocoaModifier)
{
  UInt32 carbonModifier = 0;
  if (aCocoaModifier & NSAlphaShiftKeyMask) {
    carbonModifier |= alphaLock;
  }
  if (aCocoaModifier & NSControlKeyMask) {
    carbonModifier |= controlKey;
  }
  if (aCocoaModifier & NSAlternateKeyMask) {
    carbonModifier |= optionKey;
  }
  if (aCocoaModifier & NSShiftKeyMask) {
    carbonModifier |= shiftKey;
  }
  if (aCocoaModifier & NSCommandKeyMask) {
    carbonModifier |= cmdKey;
  }
  if (aCocoaModifier & NSNumericPadKeyMask) {
    carbonModifier |= kEventKeyModifierNumLockMask;
  }
  if (aCocoaModifier & NSFunctionKeyMask) {
    carbonModifier |= kEventKeyModifierFnMask;
  }
  return carbonModifier;
}

// While HiDPI support is not 100% complete and tested, we'll have a pref
// to allow it to be turned off in case of problems (or for testing purposes).

// gfx.hidpi.enabled is an integer with the meaning:
//    <= 0 : HiDPI support is disabled
//       1 : HiDPI enabled provided all screens have the same backing resolution
//     > 1 : HiDPI enabled even if there are a mixture of screen modes

// All the following code is to be removed once HiDPI work is more complete.

static bool sHiDPIEnabled = false;
static bool sHiDPIPrefInitialized = false;

// static
bool
nsCocoaUtils::HiDPIEnabled()
{
  if (!sHiDPIPrefInitialized) {
    sHiDPIPrefInitialized = true;

    int prefSetting = Preferences::GetInt("gfx.hidpi.enabled", 1);
    if (prefSetting <= 0) {
      return false;
    }

    // prefSetting is at least 1, need to check attached screens...

    int scaleFactors = 0; // used as a bitset to track the screen types found
    NSEnumerator *screenEnum = [[NSScreen screens] objectEnumerator];
    while (NSScreen *screen = [screenEnum nextObject]) {
      NSDictionary *desc = [screen deviceDescription];
      if ([desc objectForKey:NSDeviceIsScreen] == nil) {
        continue;
      }
      CGFloat scale =
        [screen respondsToSelector:@selector(backingScaleFactor)] ?
          [screen backingScaleFactor] : 1.0;
      // Currently, we only care about differentiating "1.0" and "2.0",
      // so we set one of the two low bits to record which.
      if (scale > 1.0) {
        scaleFactors |= 2;
      } else {
        scaleFactors |= 1;
      }
    }

    // Now scaleFactors will be:
    //   0 if no screens (supporting backingScaleFactor) found
    //   1 if only lo-DPI screens
    //   2 if only hi-DPI screens
    //   3 if both lo- and hi-DPI screens
    // We'll enable HiDPI support if there's only a single screen type,
    // OR if the pref setting is explicitly greater than 1.
    sHiDPIEnabled = (scaleFactors <= 2) || (prefSetting > 1);
  }

  return sHiDPIEnabled;
}
