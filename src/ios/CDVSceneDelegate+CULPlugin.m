//
//  CDVSceneDelegate+CULPlugin.m
//
//  Cordova-iOS 8+ SceneDelegate category for handling universal links.
//

#import "CDVSceneDelegate+CULPlugin.h"
#import "CULPlugin.h"
#import <Cordova/CDVViewController.h>
#import <objc/runtime.h>

static NSString *const PLUGIN_NAME = @"UniversalLinks";

@implementation CDVSceneDelegate (CULPlugin)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(scene:willConnectToSession:options:));
        Method swizzled = class_getInstanceMethod(self, @selector(cul_scene:willConnectToSession:options:));
        if (original && swizzled) {
            method_exchangeImplementations(original, swizzled);
        }
    });
}

// Swizzled willConnectToSession — handles cold launch universal links
- (void)cul_scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    // Call original implementation (after swizzle, cul_ points to the original)
    [self cul_scene:scene willConnectToSession:session options:connectionOptions];

    // Handle universal links from cold launch
    for (NSUserActivity *userActivity in connectionOptions.userActivities) {
        if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && userActivity.webpageURL != nil) {
            [[NSUserDefaults standardUserDefaults] setObject:userActivity.webpageURL.absoluteString forKey:@"AppUniversalLaunchingUrl"];
            break;
        }
    }
}

// Handles universal links when app is running (foreground/background resume)
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    if (![userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] || userActivity.webpageURL == nil) {
        return;
    }

    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIWindow *window = windowScene.windows.firstObject;
    if (window == nil) {
        return;
    }

    CDVViewController *viewController = (CDVViewController *)window.rootViewController;
    if (viewController == nil) {
        return;
    }

    CULPlugin *plugin = (CULPlugin *)[viewController getCommandInstance:PLUGIN_NAME];
    if (plugin != nil) {
        [plugin handleUserActivity:userActivity];
    }
}

@end
