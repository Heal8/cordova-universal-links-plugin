//
//  AppDelegate+CULPlugin.m
//
//  Created by Nikolay Demyankov on 15.09.15.
//

#import "AppDelegate+CULPlugin.h"
#import "CULPlugin.h"

/**
 *  Plugin name in config.xml
 */
static NSString *const PLUGIN_NAME = @"UniversalLinks";

@implementation AppDelegate (CULPlugin)

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *))restorationHandler {
    // ignore activities that are not for Universal Links
    if (![userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] || userActivity.webpageURL == nil) {
        return NO;
    }
    
    // get instance of the plugin and let it handle the userActivity object
    CULPlugin *plugin = [self.viewController getCommandInstance:PLUGIN_NAME];
    if (plugin == nil) {
        return NO;
    }
    
    return [plugin handleUserActivity:userActivity];
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    if (launchOptions != nil) {
        NSDictionary *userActivityDictionary = [launchOptions objectForKey:UIApplicationLaunchOptionsUserActivityDictionaryKey];
        if (userActivityDictionary != nil) {
            __block NSString *url = nil;
            [userActivityDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                if (url == nil && obj != nil && [obj isKindOfClass:[NSUserActivity class]]) {
                    NSUserActivity *userActivity = (NSUserActivity *)obj;
                    if (userActivity.webpageURL != nil) {
                        url = userActivity.webpageURL.absoluteString;
                    }
                }
            }];
            if (url != nil) {
                NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
                if (prefs != nil) {
                    [prefs setObject:url forKey:@"AppUniversalLaunchingUrl"];
                }
            }
        }
    }
    return YES;
}

@end
