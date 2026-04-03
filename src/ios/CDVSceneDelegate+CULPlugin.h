//
//  CDVSceneDelegate+CULPlugin.h
//
//  Cordova-iOS 8+ SceneDelegate category for handling universal links.
//

#import <Cordova/CDVSceneDelegate.h>

/**
 *  Category for CDVSceneDelegate that adds universal link handling
 *  via scene:continueUserActivity: and swizzles scene:willConnectToSession:options:
 *  to handle cold launch universal links.
 */
@interface CDVSceneDelegate (CULPlugin)

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;

@end
