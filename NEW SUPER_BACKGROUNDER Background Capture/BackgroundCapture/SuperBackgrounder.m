//
//  SuperBackgrounder.m
//  SuperBackgrounder
//
//  Created by marek on 05/03/2013.
//  Copyright (c) 2013 Marek Bell. All rights reserved.
//

#import "SuperBackgrounder.h"

@interface SuperBackgrounder() <CLLocationManagerDelegate>

@property (strong) CLLocationManager *locationManager;
@property UIBackgroundTaskIdentifier backgroundTaskIdentifier;
@property (strong) NSTimer *kickTimer;
//@property (strong ) NSTimer *aliveCheckTimer;

@end

@implementation SuperBackgrounder

+ (id)sharedSuperBackgrounder {
    static id ssb = nil;
    if (!ssb) {
        ssb = [[self alloc] init];
    }
    return ssb;
}

- (id)init {
    self = [super init];
    if (self) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
        self.locationManager.distanceFilter = kCLDistanceFilterNone;
//        self.aliveCheckTimer = [NSTimer scheduledTimerWithTimeInterval:5.0f target:self selector:@selector(aliveCheck:) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)aliveCheck:(NSTimer *)timer {
    NSLog(@"Alive %f", [[UIApplication sharedApplication] backgroundTimeRemaining]);
}

- (void)locationManager:(CLLocationManager *)manager
	 didUpdateLocations:(NSArray *)locations {
    NSLog(@"Got a location, resetting expiration");
    if (self.isKeepingAwake) {
        [self redoBackgroundTask];
    }
    [self.locationManager stopUpdatingLocation];
}

- (BOOL)isKeepingAwake {
    return self.kickTimer.isValid;
}

- (void)redoBackgroundTask {
    UIBackgroundTaskIdentifier old = self.backgroundTaskIdentifier;
    self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"One dead");
    }];
    if (old > 0) {
        NSLog(@"Ending background task %d", old);
        [[UIApplication sharedApplication] endBackgroundTask:old];
    }
}

- (void)startKeepingAwake {
    NSLog(@"Starting awake");
    [self.kickTimer invalidate];
    [self redoBackgroundTask];
    self.kickTimer = [NSTimer scheduledTimerWithTimeInterval:300.0f target:self selector:@selector(kickTick:) userInfo:nil repeats:YES];
    [self.locationManager startUpdatingLocation];
}

- (void)stopKeepingAwake {
    NSLog(@"Stopping awake");
    [self.locationManager stopUpdatingLocation];
    [self.kickTimer invalidate];
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
}

- (void)kickTick:(NSTimer *)timer {
    NSLog(@"KickTick remaining: %f", [[UIApplication sharedApplication] backgroundTimeRemaining]);
    [self.locationManager startUpdatingLocation];
}

@end
