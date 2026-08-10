//
//  CULPlugin.m
//
//  Created by Nikolay Demyankov on 14.09.15.
//

#import "CULPlugin.h"
#import "CULConfigXmlParser.h"
#import "CULPath.h"
#import "CULHost.h"
#import "CDVPluginResult+CULPlugin.h"
#import "CDVInvokedUrlCommand+CULPlugin.h"
#import "CULConfigJsonParser.h"

/**
 *  Keys the launching url is stashed under by the app/scene delegate, and how long that stash stays
 *  valid. NSUserDefaults survives the process, so the timestamp is what keeps a url stashed by one
 *  launch from being dispatched by a later, unrelated one (see consumePendingLaunchUrl).
 */
static NSString *const LAUNCH_URL_KEY = @"AppUniversalLaunchingUrl";
static NSString *const LAUNCH_URL_TIME_KEY = @"AppUniversalLaunchingUrlTime";
static const NSTimeInterval LAUNCH_URL_MAX_AGE = 120;

@interface CULPlugin() {
    NSArray *_supportedHosts;
    CDVPluginResult *_storedEvent;
    NSMutableDictionary<NSString *, NSString *> *_subscribers;
    BOOL _initializing;
    NSString *_launchUrl;
}

@end

@implementation CULPlugin

#pragma mark Public API

- (void)pluginInitialize {
    [self localInit];
    // Can be used for testing.
    // Just uncomment, close the app and reopen it. That will simulate application launch from the link.
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume:) name:UIApplicationWillEnterForegroundNotification object:nil];
    self->_initializing = YES;
    self->_launchUrl = @"";
    [self consumePendingLaunchUrl];
}

//- (void)onResume:(NSNotification *)notification {
//    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
//    [activity setWebpageURL:[NSURL URLWithString:@"http://site2.com/news/page?q=1&v=2#myhash"]];
//    
//    [self handleUserActivity:activity];
//}

- (void)handleOpenURL:(NSNotification*)notification {
    id url = notification.object;
    if (![url isKindOfClass:[NSURL class]]) {
        return;
    }
    
    CULHost *host = [self findHostByURL:url];
    if (host) {
        [self storeEventWithHost:host originalURL:url];
    }
}

- (BOOL)handleUserActivity:(NSUserActivity *)userActivity {
    [self localInit];
    
    NSURL *launchURL = userActivity.webpageURL;
    CULHost *host = [self findHostByURL:launchURL];
    if (host == nil) {
        return NO;
    }
    
    [self storeEventWithHost:host originalURL:launchURL];
    
    self->_initializing = NO;

    return YES;
}

- (void)onAppTerminate {
    _supportedHosts = nil;
    _subscribers = nil;
    _storedEvent = nil;
    
    [super onAppTerminate];
}

#pragma mark Private API

- (void)localInit {
    if (_supportedHosts) {
        return;
    }
    
    _subscribers = [[NSMutableDictionary alloc] init];
    
    // Get supported hosts from the config.xml or www/ul.json.
    // For now priority goes to json config.
    _supportedHosts = [self getSupportedHostsFromPreferences];
}

- (NSArray<CULHost *> *)getSupportedHostsFromPreferences {
    NSString *jsonConfigPath = [[NSBundle mainBundle] pathForResource:@"ul" ofType:@"json" inDirectory:@"www"];
    if (jsonConfigPath) {
        return [CULConfigJsonParser parseConfig:jsonConfigPath];
    }
    
    return [CULConfigXmlParser parse];
}

/**
 *  Turn a cold-launch url into a stored event.
 *
 *  On the UIScene lifecycle (cordova-ios 8+) the launch activity is only ever handed to
 *  scene:willConnectToSession:, which stashes the url in NSUserDefaults - continueUserActivity is
 *  never called for it, so handleUserActivity: never runs and nothing dispatches the event. Without
 *  this the url was read into _launchUrl as a payload field only, and a link that cold-started the
 *  app was silently dropped (the app just opened on its default screen).
 *
 *  Called both from pluginInitialize and from the JS subscribe, because the ordering between the two
 *  is not guaranteed: this plugin is onload=true, so pluginInitialize runs inside the original
 *  scene:willConnectToSession: - i.e. before the stash is written. The subscribe call always happens
 *  afterwards. The key is removed on read, so whichever runs first wins and the event fires once.
 */
- (void)consumePendingLaunchUrl {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if (prefs == nil) {
        return;
    }

    NSString *launchUrl = [prefs stringForKey:LAUNCH_URL_KEY];
    if (launchUrl.length == 0) {
        return;
    }

    // read the age before dropping the stash, and drop it either way: a url that is not dispatched
    // now will never be, and leaving it behind is what would let it fire on a later launch
    NSTimeInterval stashedAt = [prefs doubleForKey:LAUNCH_URL_TIME_KEY];
    NSTimeInterval age = [[NSDate date] timeIntervalSince1970] - stashedAt;
    [prefs removeObjectForKey:LAUNCH_URL_KEY];
    [prefs removeObjectForKey:LAUNCH_URL_TIME_KEY];

    // the stash outlives the process: if the app is killed between the scene stashing the url and
    // the web view subscribing, it would otherwise still be sitting there on the next, ordinary
    // launch and send the user to a screen they never asked to open. Only a url stashed by the
    // launch we are currently serving is worth dispatching - anything without a timestamp (an
    // older build), from the future (clock moved) or too old is dropped.
    if (stashedAt <= 0 || age < 0 || age > LAUNCH_URL_MAX_AGE) {
        return;
    }

    self->_launchUrl = launchUrl;

    NSURL *url = [NSURL URLWithString:launchUrl];
    if (url == nil) {
        return;
    }

    [self localInit];
    CULHost *host = [self findHostByURL:url];
    if (host == nil) {
        return;
    }

    [self storeEventWithHost:host originalURL:url];
}

/**
 *  Store event data for future use.
 *  If we are resuming the app - try to consume it.
 *
 *  @param host        host that matches the launch url
 *  @param originalUrl launch url
 */
- (void)storeEventWithHost:(CULHost *)host originalURL:(NSURL *)originalUrl {
    _storedEvent = [CDVPluginResult resultWithHost:host originalURL:originalUrl launchUrl:self->_launchUrl initializing:self->_initializing];
    [self tryToConsumeEvent];
}

/**
 *  Find host entry that corresponds to launch url.
 *
 *  @param  launchURL url that launched the app
 *  @return host entry; <code>nil</code> if none is found
 */
- (CULHost *)findHostByURL:(NSURL *)launchURL {
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:launchURL resolvingAgainstBaseURL:YES];
    CULHost *host = nil;
    for (CULHost *supportedHost in _supportedHosts) {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"self LIKE[c] %@", supportedHost.name];
        if ([pred evaluateWithObject:urlComponents.host]) {
            host = supportedHost;
            break;
        }
    }
    
    return host;
}

#pragma mark Methods to send data to JavaScript

/**
 *  Try to send event to the web page.
 *  If there is a subscriber for the event - it will be consumed. 
 *  If not - it will stay until someone subscribes to it.
 */
- (void)tryToConsumeEvent {
    if (_subscribers.count == 0 || _storedEvent == nil) {
        return;
    }
    
    NSString *storedEventName = [_storedEvent eventName];
    for (NSString *eventName in _subscribers) {
        if ([storedEventName isEqualToString:eventName]) {
            NSString *callbackID = _subscribers[eventName];
            [self.commandDelegate sendPluginResult:_storedEvent callbackId:callbackID];
            _storedEvent = nil;
            break;
        }
    }
}

#pragma mark Methods, available from JavaScript side

- (void)jsSubscribeForEvent:(CDVInvokedUrlCommand *)command {
    // recovered here as well as in pluginInitialize - on the scene lifecycle the stash is written
    // after this plugin has already been initialized, so subscribe time is the first point at which
    // a cold-launch url is reliably visible. Kept ahead of the _initializing reset so the event that
    // reaches JS still reports initializing:YES, matching a real cold start.
    [self consumePendingLaunchUrl];
    self->_initializing = NO;

    NSString *eventName = [command eventName];
    if (eventName.length == 0) {
        return;
    }
    
    _subscribers[eventName] = command.callbackId;
    [self tryToConsumeEvent];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@""];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)jsUnsubscribeFromEvent:(CDVInvokedUrlCommand *)command {
    self->_initializing = NO;

    NSString *eventName = [command eventName];
    if (eventName.length == 0) {
        return;
    }
    
    [_subscribers removeObjectForKey:eventName];
}

- (void)jsGetLaunchUrl:(CDVInvokedUrlCommand *)command {
    self->_initializing = NO;

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{
        @"url" : self->_launchUrl
    }];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

@end
