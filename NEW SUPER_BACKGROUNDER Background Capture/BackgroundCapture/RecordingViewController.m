//
//  RecordingViewController.m
//  BackgroundCapture
//
//  Created by marek on 04/03/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "RecordingViewController.h"

#import "VideoCapture.h"
#include <dlfcn.h>
#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCallCenter.h>
//#import "MMPDeepSleepPreventer.h"
#import "VideoAndAudioMerger.h"
#import "MBProgressHUD.h"
#import "DropboxUpload.h"
#import "SuperBackgrounder.h"
#import "Reachability.h"

#define UIKITPATH "/System/Library/Framework/UIKit.framework/UIKit"
#define SBSERVPATH "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"

@interface RecordingViewController () <VideoCaptureDelegate, VideoAndAudioMergerDelegate>

@property (weak, nonatomic) IBOutlet UILabel *timingLabel;

@property (strong) NSTimer *timer;
@property NSTimeInterval startTime;

@property (strong) CTCallCenter *callCenter;

@property (strong) VideoCapture *videoCapture;
@property (strong) VideoAndAudioMerger *videoAndAudioMerger;

@property (weak, nonatomic) IBOutlet UIButton *doneButton;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@property (weak, nonatomic) IBOutlet UILabel *orientationLabel;

@property (strong) NSArray *gearsArray;

@property mach_port_t *sbPort;

@property BOOL lastScreenLockStatus;
@property BOOL audioSuspendedForCall;

@end

@implementation RecordingViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.videoCapture = [VideoCapture sharedVideoCapture];
    self.videoCapture.delegate = self;
    
    self.videoAndAudioMerger = [VideoAndAudioMerger sharedVideoAndAudioMerger];
    self.videoAndAudioMerger.delegate = self;
    
    void *uikit = dlopen(UIKITPATH, RTLD_LAZY);
    int (*SBSSpringBoardServerPort)() = dlsym(uikit, "SBSSpringBoardServerPort");
    mach_port_t *p = (mach_port_t *)SBSSpringBoardServerPort();
    dlclose(uikit);
    self.sbPort = p;
    self.audioSuspendedForCall = NO;
    
    UIImage *buttonImage = [[UIImage imageNamed:@"blackButton.png"]
                            resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
    UIImage *buttonImageHighlight = [[UIImage imageNamed:@"blackButtonHighlight.png"]
                                     resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
    [self.doneButton setBackgroundImage:buttonImage forState:UIControlStateNormal]
    ;
    [self.doneButton setBackgroundImage:buttonImageHighlight forState:UIControlStateHighlighted];
    [self.doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    

    
    /*LETS MAKE A CRASH!
    
     NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/creation/385575055.551999"];
    NSString *vidpath = [dir stringByAppendingPathComponent:@"video.mp4"];
    NSString *audpath = [dir stringByAppendingPathComponent:@"audio.m4a"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];

    if(![[NSFileManager defaultManager] fileExistsAtPath:vidpath]){
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"corrupt" ofType:@"avi"] toPath:vidpath error:&error];
        if(error){
            NSLog(@"COPY FAILED: %@", error);
        }
    }
    if(![[NSFileManager defaultManager] fileExistsAtPath:audpath]){
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"corrupt" ofType:@"avi"] toPath:audpath error:nil];
        if(error){
            NSLog(@"COPY FAILED: %@", error);
        }
    }
    /***************************/
    
    
    NSMutableArray *mar = [NSMutableArray array];
    for (int i = 0; i < 36; i++) {
        NSString *s = [NSString stringWithFormat:@"GearAnimation%d", i];
        [mar addObject:[UIImage imageNamed:s]];
    }
    self.gearsArray = mar;
    
    
    
    //Lets set up some notifications stop and start the audio recorder when calls are made
    
    //Just registering for the events seems to be keeping us alive...
    
    self.callCenter = [[CTCallCenter alloc] init];
    [self.callCenter setCallEventHandler:^(CTCall* call){
        NSLog(@"Call Event");
        if([call.callState isEqualToString:CTCallStateDialing])
        {
            //The call state, before connection is established, when the user initiates the call.
            
            /*dispatch_sync(dispatch_get_main_queue(), ^(void) {
                NSLog(@"Call state dialing");
                [[NSNotificationCenter defaultCenter] postNotificationName:@"CallStartingSuspendAudio" object:nil];
            });*/
        }
        if([call.callState isEqualToString:CTCallStateIncoming])
        {
            //The call state, before connection is established, when a call is incoming but not yet answered by the user.
            /*
            dispatch_sync(dispatch_get_main_queue(), ^(void) {
                NSLog(@"Call state incoming");
                [[NSNotificationCenter defaultCenter] postNotificationName:@"CallStartingSuspendAudio" object:nil];
            });
             */
        }
        
        if([call.callState isEqualToString:CTCallStateConnected])
        {
            //The call state when the call is fully established for all parties involved.
            //Shouldn't need anything here?
           //NSLog(@"Call state connected");
        }
        
        if([call.callState isEqualToString:CTCallStateDisconnected])
        {
            //The call state Ended.
            /*
            dispatch_sync(dispatch_get_main_queue(), ^(void) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"CallEndedStartAudio" object:nil];
                NSLog(@"Call state ended");
            });
             */
        }
        
    }];
    
    //Shouldn't need these, right?
    /*
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(CallStartingSuspendAudio:) name:@"CallStartingSuspendAudio" object:nil];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(CallEndedStartAudio:) name:@"CallEndedStartAudio" object:nil];
    */
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self startRecording:self];
    
    NSString *orientation = nil;
    switch (self.videoCapture.interfaceOrientationDesired) {
        case UIInterfaceOrientationLandscapeLeft:
            orientation = @"Landscape Left";
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            orientation = @"Portrait Upside Down";
            break;
        case UIInterfaceOrientationPortrait:
            orientation = @"Portrait";
            break;
        case UIInterfaceOrientationLandscapeRight:
            orientation = @"Landscape Right";
            break;
        default:
            orientation = @"Unknown!";
            break;
    }
    self.orientationLabel.text = [@"Orientation: " stringByAppendingString:orientation];
    
    
    //Lets do a check here to see if the processing hud is stuck, can't consistently cause it to debug but it still happens
    //Spamming processorend doesn't seem like a good idea...
    //This would only happen if PoE spawns and never returns.
    //All paths out of PoE seem to call the delegate, so that means PoE is siliently crashing outside the try blocks or blocking all together
    //
    
//    [self.timer invalidate];
//    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
//    [self.timer invalidate];
    [super viewWillDisappear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (NSString *)secondsToMinutesAndSecondsString:(int)ts {
    int seconds = ts % 60;
    int minutes = (ts / 60);
    
    return [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
}

- (void)timerTick:(NSTimer *)timer {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        return;
    }
    NSTimeInterval seconds = [NSDate timeIntervalSinceReferenceDate] - self.startTime;
    self.timingLabel.text = [NSString stringWithFormat:@"Recording: %@", [self secondsToMinutesAndSecondsString:seconds]];
}

//- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
//    CGPoint p = CGPointMake(self.view.bounds.size.width / 2.0f, self.view.bounds.size.height / 2.0f);
//    self.timingLabel.center = p;
//}

#pragma mark - AlertView Delegate

//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
//    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
//    if ([title isEqualToString:@"Delete Recording"]) {
//        [self dismissViewControllerAnimated:YES completion:^{
//            [self.delegate recordingViewControllerWantsDelete:self];
//        }];
//    }
//}

#pragma mark - Actions

- (IBAction)done:(id)sender {
//    [self stopRecording:self];
//    [self dismissViewControllerAnimated:YES completion:^{
//        [self.delegate recordingViewControllerWantsCompletion:self];
//    }];
}

- (IBAction)cancel:(id)sender {
//    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Delete Recording" message:@"Recorded video will be lost if you delete. Really delete and discard video?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Delete Recording", nil];
//    [av show];
}

#pragma mark - Video and Audio Merger Deleger

- (void)videoAndAudioMerger:(VideoAndAudioMerger *)vaam processedDirectory:(NSString *)dir toPath:(NSString *)path {
    NSLog(@"Processed a file from dir %@ to %@", dir, path);
    
    NSString *target = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/merged"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
    target = [target stringByAppendingPathComponent:[path lastPathComponent]];
    [[NSFileManager defaultManager] moveItemAtPath:path toPath:target error:&error];
    if (error) {
        NSLog(@"%@", error);
        //abort();
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:dir error:&error];
    if (error) {
        NSLog(@"%@", error);
        //abort();
    }

    //Moving to the dropbox upload script.
    
    //The app will now upload everything that has not been auto-uploaded already even if it was made outside an auto-upload session when the auto-upload is turned on.

    [[DropboxUpload sharedDropboxUpload] queueFileAtPath:target];
    
    [self processOrEnd];
}

- (void)videoAndAudioMerger:(VideoAndAudioMerger *)vaam failedToProcessDirectory:(NSString *)dir {
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dir error:&error];
    if (error) {
        NSLog(@"Error deleting bad dir");
    }
    [self processOrEnd];
}

#pragma mark - Processing

- (void)dismissOnMain {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }
//    [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
    [[SuperBackgrounder sharedSuperBackgrounder] stopKeepingAwake];
    [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissOnMainWithSuccess {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }
//    [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
    [[SuperBackgrounder sharedSuperBackgrounder] stopKeepingAwake];
    [MBProgressHUD hideAllHUDsForView:self.view animated:YES];
    [self dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(recordingViewControllerCompletedWithSuccess:)]) {
            [self.delegate recordingViewControllerCompletedWithSuccess:self];
        }
    }];
}

- (void)updateProcessingUI:(NSNumber *)left {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:left waitUntilDone:NO];
        return;
    }
    [MBProgressHUD hideAllHUDsForView:self.view animated:NO];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeIndeterminate;
    hud.labelText = [NSString stringWithFormat:@"Processing (%@ left)", left];
}

- (void)processOrEnd {
    NSError *error = nil;
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/creation"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&error];
    if (error) {
        NSLog(@"Error listing creation dir: %@", error);
        [self dismissOnMain];
        return;
    }
    if (files.count <= 0) {
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            [self dismissOnMain];
            return;
        } else {
            [MBProgressHUD hideAllHUDsForView:self.view animated:NO];
            return;
        }
    }
    [self updateProcessingUI:[NSNumber numberWithInt:files.count]];
    NSString *path = [dir stringByAppendingPathComponent:[files objectAtIndex:0]];
    [self.videoAndAudioMerger processFilesInDirectory:path];
}

#pragma mark - Video Capture Delegate

- (void)videoCapture:(VideoCapture *)vc completedCaptureTo:(NSURL *)url {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        NSLog(@"Finished recording in background");
//        return;
    }
    [self processOrEnd];
}

#pragma mark - Lock State

- (BOOL)isScreenLocked {
	void *sbserv = dlopen(SBSERVPATH, RTLD_LAZY);
	void* (*SBGetScreenLockStatus)(mach_port_t* port, BOOL *lockStatus, BOOL *passcoded) = dlsym(sbserv, "SBGetScreenLockStatus");
	BOOL ab, bb = NO;
    
	SBGetScreenLockStatus(self.sbPort, &ab, &bb);
	NSLog(@"Locked = %d, Passcoded = %d", ab, bb);
	dlclose(sbserv);
	return ab;
}

- (void)lockStateChanged:(NSNotification *)note {
    BOOL current = [self isScreenLocked];
    if (self.lastScreenLockStatus != current) {
        self.lastScreenLockStatus = current;
        if (self.lastScreenLockStatus) {
            if (self.videoCapture.recordAudio) {
                [[SuperBackgrounder sharedSuperBackgrounder] startKeepingAwake];
//                [[MMPDeepSleepPreventer sharedDeepSleepPreventer] startPreventSleep];
            }
            NSLog(@"Stopping video because screen lock detected");
            [self.videoCapture stopRecordingAndKeepAudioActive:YES];
        } else {
            NSLog(@"Starting video because screen unlock detected");
            [self.videoCapture startRecording];
            if (self.videoCapture.recordAudio) {
//                [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
                [[SuperBackgrounder sharedSuperBackgrounder] stopKeepingAwake];
            }
        }
    }
}


#pragma mark - Phonecalls
//Not causing problems when the audio isn't active, so this should be OK?

- (void)CallStartingSuspendAudio:(NSNotification *)note {
    NSLog(@"CallStartingSuspendAudio: %d / %d", self.videoCapture.recordAudio, self.audioSuspendedForCall);
    
    
    if (self.videoCapture.recordAudio) {
        self.audioSuspendedForCall = YES;
        [self.videoCapture stopRecording];
        self.videoCapture.recordAudio = NO;
        [self.videoCapture startRecording];
        //But want to keep the backgrounding alive or we don't get the start notification
    }
}

//Can change it to keep recording without audio during the call, then turn it back on after?

- (void)CallEndedStartAudio:(NSNotification *)note {
     NSLog(@"CallEndedStartAudio");
    if (self.audioSuspendedForCall) {
        [self.videoCapture stopRecording];
        self.videoCapture.recordAudio = YES;
        self.audioSuspendedForCall = NO;
        [self.videoCapture startRecording];
    }
}

#pragma mark - App back and forward

- (void)appWentBack:(NSNotification *)note {
    [self.imageView stopAnimating];
}

- (void)appCameForward:(NSNotification *)note {
    [self.imageView startAnimating];
}

#pragma mark - Recording start/stop

- (IBAction)startRecording:(id)sender {
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
    self.lastScreenLockStatus = [self isScreenLocked];
    
    if (!self.videoCapture.recordAudio) {
        [[SuperBackgrounder sharedSuperBackgrounder] startKeepingAwake];
//        [[MMPDeepSleepPreventer sharedDeepSleepPreventer] startPreventSleep];
    }
    
    self.videoCapture.interfaceOrientationDesired = self.interfaceOrientation;
    [self.videoCapture startRecording];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lockStateChanged:) name:@"LockStateChange" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWentBack:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appCameForward:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    self.imageView.animationImages = self.gearsArray;
    self.imageView.animationDuration = 2.0f;
    [self.imageView startAnimating];
}

-(void)cancelRecording{
    [self.timer invalidate];
    self.timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[SuperBackgrounder sharedSuperBackgrounder] stopKeepingAwake];
    [self.videoCapture stopRecording];
    [self dismissOnMain];
}

- (IBAction)stopRecording:(id)sender {
    [self.timer invalidate];
    self.timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.videoCapture stopRecording];
    [[SuperBackgrounder sharedSuperBackgrounder] stopKeepingAwake];
//    [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeIndeterminate;
    hud.labelText = @"Processing...";
}

@end
