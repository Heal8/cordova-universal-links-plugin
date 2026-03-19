//
//  CDVSceneDelegate+CULPlugin.m
//
//  Category on CDVSceneDelegate to handle Universal Links
//  in Cordova iOS 8+ scene-based lifecycle.
//
//  Cold launch: swizzles scene:willConnectToSession:options: to store
//  the launch URL in NSUserDefaults for CULPlugin.pluginInitialize to read.
//
//  Warm launch: adds scene:continueUserActivity: to call
//  CULPlugin.handleUserActivity: directly.
//

#import "CDVSceneDelegate+CULPlugin.h"
#import "CULPlugin.h"
#import <Cordova/CDVViewController.h>
#import <objc/runtime.h>

static NSString *const CUL_PLUGIN_NAME = @"UniversalLinks";
static NSString *const CUL_LAUNCH_URL_KEY = @"AppUniversalLaunchingUrl";

#pragma mark - Helper functions

static NSURL *CULURLFromUserActivities(NSSet<NSUserActivity *> *userActivities) {
    for (NSUserActivity *activity in userActivities) {
        if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && activity.webpageURL != nil) {
            return activity.webpageURL;
        }
    }
    return nil;
}

static CULPlugin *CULGetPluginInstance(CDVSceneDelegate *sceneDelegate) {
    UIViewController *rootVC = sceneDelegate.window.rootViewController;
    if (![rootVC isKindOfClass:[CDVViewController class]]) {
        return nil;
    }
    return (CULPlugin *)[(CDVViewController *)rootVC getCommandInstance:CUL_PLUGIN_NAME];
}

#pragma mark - CDVSceneDelegate (CULPlugin)

@implementation CDVSceneDelegate (CULPlugin)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [self class];

        SEL originalSelector = @selector(scene:willConnectToSession:options:);
        SEL swizzledSelector = @selector(cul_scene:willConnectToSession:options:);

        Method originalMethod = class_getInstanceMethod(cls, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);

        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

// Swizzled scene:willConnectToSession:options: — handles cold launch universal links.
// After swizzling, calling cul_scene:willConnectToSession:options: invokes the original implementation.
- (void)cul_scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // Call original implementation first (handles URLContexts for custom URL schemes)
    [self cul_scene:scene willConnectToSession:session options:connectionOptions];

    // Handle universal links from connectionOptions.userActivities
    NSURL *url = CULURLFromUserActivities(connectionOptions.userActivities);
    if (url != nil) {
        // Cold launch: plugin is not yet initialized.
        // Store URL in NSUserDefaults so CULPlugin.pluginInitialize can read it.
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject:url.absoluteString forKey:CUL_LAUNCH_URL_KEY];
        [prefs synchronize];
    }
}

// scene:continueUserActivity: — handles warm launch universal links.
// CDVSceneDelegate does not implement this method, so adding it via category is safe.
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    if (![userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] || userActivity.webpageURL == nil) {
        return;
    }

    CULPlugin *plugin = CULGetPluginInstance(self);
    if (plugin != nil) {
        [plugin handleUserActivity:userActivity];
    }
}

@end
