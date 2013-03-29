//
//  DropboxUpload.m
//  BackgroundCapture
//
//  Created by marek on 06/03/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "DropboxUpload.h"
#include <dlfcn.h>
#import <CoreTelephony/CTCall.h>
#import <CoreTelephony/CTCallCenter.h>
#import "Reachability.h"

#define UIKITPATH "/System/Library/Framework/UIKit.framework/UIKit"
#define SBSERVPATH "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"

@interface DropboxUpload() <DBSessionDelegate, DBNetworkRequestDelegate, DBRestClientDelegate, UIAlertViewDelegate>

@property UIBackgroundTaskIdentifier uploadTask;

@property (readonly) BOOL uploading;

@property (strong) NSTimer *timer;

@property mach_port_t *sbPort;

@property (strong) NSString *relinkUserId;

@property BOOL userWarnedOfRelink;

@property (strong) NSString *currentlyUploadingFile;

@end

@implementation DropboxUpload

+ (id)sharedDropboxUpload {
    static id sdu = nil;
    if (!sdu) {
        sdu = [[self alloc] init];
    }
    return sdu;
}

- (id)init {
    self = [super init];
    if (self) {
        void *uikit = dlopen(UIKITPATH, RTLD_LAZY);
        int (*SBSSpringBoardServerPort)() = dlsym(uikit, "SBSSpringBoardServerPort");
        mach_port_t *p = (mach_port_t *)SBSSpringBoardServerPort();
        dlclose(uikit);
        self.sbPort = p;
        self.uploadTask = UIBackgroundTaskInvalid;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dropboxLoginHandled:) name:@"DropboxLoginHandled" object:nil];
        
        [self initDropbox];
    }
    return self;
}

- (BOOL)uploading {
    return self.uploadTask != UIBackgroundTaskInvalid;
}

- (void)callCompletedAll {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
        return;
    }
    if ([self.delegate respondsToSelector:@selector(dropboxUploadCompletedAllFiles:)]) {
        [self.delegate dropboxUploadCompletedAllFiles:self];
    }
}

- (NSArray *)queueArray {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"dropbox upload queue"];
}

- (NSString *)nextUploadFile {
    NSArray *qa = [self queueArray];
    return qa.count ? [qa objectAtIndex:0] : nil;
}

- (void)queueFileAtPath:(NSString *)path {
    NSArray *ar = [self queueArray];
    NSMutableArray *mar = ar.count ? [ar mutableCopy] : [NSMutableArray array];
    [mar addObject:path];
    [[NSUserDefaults standardUserDefaults] setObject:mar forKey:@"dropbox upload queue"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)removeFileAtPath:(NSString *)path {
    NSArray *ar = [self queueArray];
    NSMutableArray *mar = ar.count ? [ar mutableCopy] : [NSMutableArray array];
    [mar removeObject:path];
    [[NSUserDefaults standardUserDefaults] setObject:mar forKey:@"dropbox upload queue"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)doUploadOfFile:(NSString *)path {
    if ([self.delegate respondsToSelector:@selector(dropboxUpload:beganUploading:)]) {
        [self.delegate dropboxUpload:self beganUploading:path];
    }
    self.currentlyUploadingFile = path;
    [self.dbRestClient uploadFile:[path lastPathComponent] toPath:@"/" withParentRev:nil fromPath:path];
}

// shouldn't be copying this same code into multiple classes... oh well
- (BOOL)isScreenLocked {
	void *sbserv = dlopen(SBSERVPATH, RTLD_LAZY);
	void* (*SBGetScreenLockStatus)(mach_port_t* port, BOOL *lockStatus, BOOL *passcoded) = dlsym(sbserv, "SBGetScreenLockStatus");
	BOOL ab, bb = NO;
    
	SBGetScreenLockStatus(self.sbPort, &ab, &bb);
	dlclose(sbserv);
	return ab;
}

- (void)timerTick:(NSTimer *)t {
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive && ![self isScreenLocked]) {
        //NSLog(@"Not checking for upload since something else is active");
        return;
    }
    
    if(!(
         ([[NSUserDefaults standardUserDefaults] boolForKey:@"auto upload to dropbox"])
         &&
         (([[NSUserDefaults standardUserDefaults] boolForKey:@"upload on battery power"]
            || [[UIDevice currentDevice] batteryState] != UIDeviceBatteryStateUnplugged)
            &
            ([[NSUserDefaults standardUserDefaults] boolForKey:@"auto upload to dropbox over cellular"]
            || [[Reachability reachabilityForLocalWiFi] currentReachabilityStatus] == ReachableViaWiFi))
         )
       ){
        
        NSLog(@"Not uploading because of flags");
           return;
    }

    
    NSArray *qa = [self queueArray];
    if (qa.count) {
        NSString *file = [qa objectAtIndex:0];
        NSLog(@"Found a file to upload, uploading %@", file);
        if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
            NSLog(@"File didn't exist, removing from queue");
            [self removeFileAtPath:file];
            return;
        }
        if (![[DBSession sharedSession] isLinked]) {
            NSLog(@"Can't upload because session is not linked");
            return;
        }
        [self.timer invalidate];
        self.timer = nil;
        UIBackgroundTaskIdentifier oldtask = self.uploadTask;
        self.uploadTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            NSLog(@"Need to do clean teardown here");
            self.uploadTask = UIBackgroundTaskInvalid;
        }];
        if (oldtask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:oldtask];
        }
        [self doUploadOfFile:[self nextUploadFile]];
    } else {
        if (self.uploadTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.uploadTask];
            self.uploadTask = UIBackgroundTaskInvalid;
        }
    }
}

- (void)beginUploading {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
}

- (void)stopUploading {
    [self.timer invalidate];
    self.timer = nil;
    [[self dbRestClient] cancelAllRequests];
    if ([self.delegate respondsToSelector:@selector(dropboxUpload:failedToUploadFile:withError:)]) {
        [self.delegate dropboxUpload:self failedToUploadFile:self.currentlyUploadingFile withError:nil];
    }
    if (self.uploadTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.uploadTask];
    }
    self.uploadTask = UIBackgroundTaskInvalid;
}

#pragma mark - UIAlertViewDelegate methods

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (index != alertView.cancelButtonIndex) {
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Relink not available" message:nil delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
        [av show];
        NSLog(@"MUST RELINK HERE");
#warning relink required here
//		[[DBSession sharedSession] linkUserId:self.relinkUserId fromController:self];
	}
	self.relinkUserId = nil;
}

#pragma mark - Dropbox

- (void)dropboxLoginHandled:(NSNotification *)note {
//    [self updateDropboxButtonUI];
//    [self refreshVideoFiles];
}

- (IBAction)dropboxLink:(id)sender {
    if ([[DBSession sharedSession] isLinked]) {
        [[DBSession sharedSession] unlinkAll];
        UIAlertView *av = [[UIAlertView alloc]
                           initWithTitle:@"Account Unlinked!" message:@"Your dropbox account has been unlinked"
                           delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
        [av show];
//        [self updateDropboxButtonUI];
    } else {
        [[DBSession sharedSession] linkFromController:self.dropboxViewController];
    }
}

- (void)initDropbox {
    NSString* appKey = DROPBOX_APP_KEY;
	NSString* appSecret = DROPBOX_APP_SECRET;
	NSString *root = kDBRootAppFolder;
	
	NSString* errorMsg = nil;
	if ([appKey rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
		errorMsg = @"Make sure you set the app key correctly";
	} else if ([appSecret rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
		errorMsg = @"Make sure you set the app secret correctly";
	} else if ([root length] == 0) {
		errorMsg = @"Set your root to use either App Folder of full Dropbox";
	} else {
		NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
		NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
		NSDictionary *loadedPlist =
        [NSPropertyListSerialization
         propertyListFromData:plistData mutabilityOption:0 format:NULL errorDescription:NULL];
		NSString *scheme = [[[[loadedPlist objectForKey:@"CFBundleURLTypes"] objectAtIndex:0] objectForKey:@"CFBundleURLSchemes"] objectAtIndex:0];
		if ([scheme isEqual:@"db-APP_KEY"]) {
			errorMsg = @"Set your URL scheme correctly in DBRoulette-Info.plist";
		}
	}
	
	DBSession* session = [[DBSession alloc] initWithAppKey:appKey appSecret:appSecret root:root];
	session.delegate = self;
    [DBRequest setNetworkRequestDelegate:self];
    
    NSLog(@"Created Dropbox session %@", session);
    
	[DBSession setSharedSession:session];
    
	if (errorMsg != nil) {
		[[[UIAlertView alloc]
          initWithTitle:@"Error Configuring Dropbox Session" message:errorMsg
          delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]
		 show];
	}
}

- (DBRestClient *)dbRestClient {
    static DBRestClient *rc = nil;
    if (![[DBSession sharedSession] isLinked]) {
        NSLog(@"Not creating rest client since db is not linked");
        rc = nil;
        return nil;
    }
    if (!rc) {
        rc = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        rc.delegate = self;
    }
    return rc;
}

#pragma mark - DBSessionDelegate methods

- (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session userId:(NSString *)userId {
	self.relinkUserId = userId;
    if (!self.userWarnedOfRelink) {
        self.userWarnedOfRelink = YES;
        [[[UIAlertView alloc]
          initWithTitle:@"Dropbox Session Ended" message:@"Do you want to relink?" delegate:self
          cancelButtonTitle:@"Cancel" otherButtonTitles:@"Relink", nil]
         show];
    }
}

#pragma mark - DBNetworkRequestDelegate methods

- (void)networkRequestStarted {
//	outstandingRequests++;
//	if (outstandingRequests > 0) {
//		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
//	}
}

- (void)networkRequestStopped {
//	outstandingRequests--;
//	if (outstandingRequests == 0) {
//		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
//	}
}

#pragma mark - DBRestClientDelegate

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath
              from:(NSString*)srcPath metadata:(DBMetadata*)metadata {
    if ([self.delegate respondsToSelector:@selector(dropboxUpload:completedUploadingFile:)]) {
        [self.delegate dropboxUpload:self completedUploadingFile:srcPath];
    }
    NSLog(@"UPLOADED: %@", srcPath);
    [self removeFileAtPath:srcPath];
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"delete autouploaded files"]){
        //Delete the local file too
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error;
        BOOL success = [fileManager removeItemAtPath:srcPath error:&error];
        if (!success) NSLog(@"Error: %@", [error localizedDescription]);
    }
    
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
    NSLog(@"File upload failed with error - %@", error);
    if ([self.delegate respondsToSelector:@selector(dropboxUpload:failedToUploadFile:withError:)]) {
        [self.delegate dropboxUpload:self failedToUploadFile:self.currentlyUploadingFile withError:error];
    }
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
}

- (void)restClient:(DBRestClient*)client uploadProgress:(CGFloat)progress
           forFile:(NSString*)destPath from:(NSString*)srcPath {
    //NSLog(@"Progress %f", progress);
    if ([self.delegate respondsToSelector:@selector(dropboxUpload:uploadingFile:withProgress:)]) {
        [self.delegate dropboxUpload:self uploadingFile:srcPath withProgress:progress];
    }
}

//Lets try chunked uploading and see if that is more robust

//
//- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath fromUploadId:(NSString *)uploadId
//          metadata:(DBMetadata *)metadata{
//    
//    
//    NSString *target = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/merged"];
//    NSError *error = nil;
//    [[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
//    target = [target stringByAppendingPathComponent:[self.fileToUploadPath lastPathComponent]];
//    [[NSFileManager defaultManager] moveItemAtPath:self.fileToUploadPath toPath:target error:&error];
//    if (error) {
//        NSLog(@"%@", error);
//        //abort(); //Lets not abort, it can fail silently if it really has to on release
//    }
//    NSLog(@"File uploaded successfully to path: %@", metadata.path);
//    self.fileToUploadPath = nil;
//    self.uploadProgress = 0;
//    [self refreshVideoFiles];
//    
//    
//}
//
//- (void)restClient:(DBRestClient *)client uploadFromUploadIdFailedWithError:(NSError *)error{
//    NSLog(@"File upload failed with error - %@", error);
//    //Try a couple more times
//    if (error != nil && (self.uploadErrorCount < MAX_ERRORS_PER_CHUNK))
//    {
//        self.uploadErrorCount++;
//        NSString* uploadId = [error.userInfo objectForKey:@"upload_id"];
//        [self.dbRestClient uploadFile:[self.fileToUploadPath lastPathComponent] toPath:@"/" withParentRev:nil fromUploadId:uploadId];
//        
//    }
//    else
//    {
//        //Cancels this upload and starts a new attempt
//        self.fileToUploadPath = nil;
//        [self refreshVideoFiles];
//        
//    }
//    
//    
//}
//
//
//
//
//- (void)restClient:(DBRestClient *)client uploadedFileChunk:(NSString *)uploadId newOffset:(unsigned long long)offset fromFile:(NSString *)localPath expires:(NSDate *)expiresDate{
//    
//    unsigned long long fileSize = [[[NSFileManager defaultManager]attributesOfItemAtPath:self.fileToUploadPath error:nil]fileSize];
//    
//    self.uploadErrorCount = 0;
//    
//    if (offset >= fileSize)
//    {
//        //Upload complete, commit the file.
//        
//        [self.dbRestClient uploadFile:[self.fileToUploadPath lastPathComponent] toPath:@"/" withParentRev:nil fromUploadId:uploadId];
//        //self.fileToUploadPath = nil;
//        //[self refreshVideoFiles];
//    }
//    else
//    {
//        //Send the next chunk and update the progress HUD.
//        //self.progressHUD.progress = (float)((float)offset / (float)fileSize);
//        self.uploadProgress = (float)((float)offset / (float)fileSize);
//        NSLog(@"Uploading %f",  self.uploadProgress);
//        [self.tableView reloadData];
//        [self.dbRestClient uploadFileChunk:uploadId offset:offset fromPath:self.fileToUploadPath];
//    }
//}
//
//- (void)restClient:(DBRestClient *)client uploadFileChunkFailedWithError:(NSError *)error
//{
//    NSLog(@"Chunk Upload Error");
//    if (error != nil && (self.uploadErrorCount < MAX_ERRORS_PER_CHUNK))
//    {
//        self.uploadErrorCount++;
//        NSString* uploadId = [error.userInfo objectForKey:@"upload_id"];
//        unsigned long long offset = [[error.userInfo objectForKey:@"offset"]unsignedLongLongValue];
//        [self.dbRestClient uploadFileChunk:uploadId offset:offset fromPath:self.fileToUploadPath];
//        
//    }
//    else
//    {
//        //Cancels this upload and starts a new attempt
//        self.fileToUploadPath = nil;
//        [self refreshVideoFiles];
//        
//    }
//}


@end