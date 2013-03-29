//
//  AppDelegate.m
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "AppDelegate.h"
#import "DropboxUpload.h"

@implementation AppDelegate


/*

void handle_event (void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event) {
	// handle the events here.
	//NSLog(@"Received event of type %2d from service %p.", IOHIDEventGetType(event), service);
	IOHIDEventType type = IOHIDEventGetType(event);
	if (type == kIOHIDEventTypeKeyboard)
	{
		NSLog(@"button event");
		
		int usagePage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsagePage);
		if (usagePage == 12) {
			int usage = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardUsage);
			int down = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldKeyboardDown);
			
			unsigned long buttonMask = 0;
			if (usage == VOL_BUTTON_UP) {
				buttonMask = R_BUTTON;
			} else if (usage == VOL_BUTTON_DOWN) {
				buttonMask = L_BUTTON;
			}
            
			if (buttonMask != 0) {
				if (down) {
					gp2x_pad_status |= buttonMask;
				} else {
					gp2x_pad_status &= ~buttonMask;
				}
				[ControllerAppDelegate().sessionController sendPadStatus:gp2x_pad_status];
			}
		}
	}
}
 
 */

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), //center
                                    NULL, // observer
                                    lockStateChanged, // callback
                                    CFSTR("com.apple.springboard.lockstate"), // event name
                                    NULL, // object
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lockStateChange:) name:@"LockStateChange" object:nil];
    
    [[DropboxUpload sharedDropboxUpload] beginUploading];
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    
    /*
    // register our event handler callback
	ioEventSystem = IOHIDEventSystemCreate(NULL);
	IOHIDEventSystemOpen(ioEventSystem, handle_event, NULL, NULL, NULL);
     */
    
    
 
    
    return YES;
}

static void lockStateChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LockStateChange" object:nil];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DropboxLoginHandled" object:nil];
        return YES;
    }
    return NO;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{

}

@end
