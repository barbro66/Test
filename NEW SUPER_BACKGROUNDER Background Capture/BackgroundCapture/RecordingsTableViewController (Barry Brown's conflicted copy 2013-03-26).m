//
//  RecordingsTableViewController.m
//  BackgroundCapture
//
//  Created by marek on 30/01/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "RecordingsTableViewController.h"
#include <dlfcn.h>
#import "VideoCapture.h"
#import "AudioCaptureTest.h"
#import "VideoAndAudioMerger.h"
#import "MMPDeepSleepPreventer.h"
#import "RecordingViewController.h"
#import "MBProgressHUD.h"
#import "FileCell.h"
#import "DropboxUpload.h"

//#define UIKITPATH "/System/Library/Framework/UIKit.framework/UIKit"
//#define SBSERVPATH "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"

#define MAX_ERRORS_PER_CHUNK 5


@interface RecordingsTableViewController() <DBSessionDelegate, DBNetworkRequestDelegate, DBRestClientDelegate, UIActionSheetDelegate, RecordingViewControllerDelegate, DropboxUploadDelegate>

@property (strong) NSMutableArray *videoFiles;
@property (strong) NSMutableArray *toUploadFiles;
@property (strong) NSMutableArray *freshlyCreated;

//@property BOOL canSkipReloadOnAppear;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *dropboxBarButtonItem;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *stopButton;

@property int uploadErrorCount;
@property float uploadProgress;

@property (strong) NSMutableArray *buttonAnimationArray;

@property (strong) NSString *relinkUserId;

@property BOOL userWarnedOfRelink;

@property (strong) NSString *fileToUploadPath;

@property (strong) VideoCapture *videoCapture;


@property (strong) UIDocumentInteractionController *interactionController;

//@property mach_port_t *sbPort;

//@property BOOL lastScreenLockStatus;

@property (strong) NSTimer *screenLockCheckTimer;
@property (strong) NSTimer *dropboxAutouploaderTimer;

@property (strong) IBOutlet UIView *uploadHeadingView;
@property (strong) IBOutlet UIProgressView *uploadProgressView;
@property (strong) IBOutlet UILabel *uploadLabel;

@end

@implementation RecordingsTableViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[DropboxUpload sharedDropboxUpload] setDropboxViewController:self];
    [[DropboxUpload sharedDropboxUpload] setDelegate:self];
    
//    [self initDropbox];
    self.fileToUploadPath = nil;
    
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    
    self.navigationItem.rightBarButtonItem.tintColor = [UIColor redColor];
    
    self.tableView.tableHeaderView = nil;
    
//    self.videoCapture = [VideoCapture sharedVideoCapture];
    
    //Set the delegate here so that the shared instance can be added to from the capture
//    VideoAndAudioMerger *vaam = [VideoAndAudioMerger sharedVideoAndAudioMerger];
//    vaam.delegate = self;
    
//    void *uikit = dlopen(UIKITPATH, RTLD_LAZY);
//    int (*SBSSpringBoardServerPort)() = dlsym(uikit, "SBSSpringBoardServerPort");
//    mach_port_t *p = (mach_port_t *)SBSSpringBoardServerPort();
//    dlclose(uikit);
//    self.sbPort = p;
    
//    self.recordButton.adjustsImageWhenDisabled = NO;
//    self.recordButton.adjustsImageWhenHighlighted = NO;
    
    
//    self.buttonAnimationArray = [NSMutableArray arrayWithCapacity:34];
//    for (int i=0; i<35; i++) {
//        NSString *s = [NSString stringWithFormat:@"record%02d", i];
//        [self.buttonAnimationArray addObject:[UIImage imageNamed:s]];
//    }
    
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideoFiles) name:@"VideoRecordingCompleted" object:nil];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVideoFiles) name:@"LeftVideoRecord" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dropboxLoginHandled:) name:@"DropboxLoginHandled" object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
//    if (!self.canSkipReloadOnAppear) {
//        self.canSkipReloadOnAppear = YES;
//        [self refreshVideoFiles];
//    }
    [self refreshVideoFiles];
    
    //[self updateDropboxButtonUI];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"RecordingSegue"]) {
        RecordingViewController *rvc = segue.destinationViewController;
        rvc.delegate = self;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)hideUploadHeader {
    [self.tableView setTableHeaderView:nil];
    
    //Remove ghosts
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"delete autouploaded files"]){
        [self refreshVideoFiles];
    }
}

#pragma mark - DropboxUpload Delegate

- (void)dropboxUpload:(DropboxUpload *)du beganUploading:(NSString *)file {
    self.tableView.tableHeaderView = self.uploadHeadingView;
    self.uploadProgressView.progress = 0.0f;
    self.uploadLabel.text = [NSString stringWithFormat:@"Starting upload of %@", [file lastPathComponent]];
}

- (void)dropboxUpload:(DropboxUpload *)du uploadingFile:(NSString *)file withProgress:(float)prog {
    self.tableView.tableHeaderView = self.uploadHeadingView;
    self.uploadLabel.text = [NSString stringWithFormat:@"Uploading %@", [file lastPathComponent]];
    self.uploadProgressView.progress = prog;
}

- (void)dropboxUpload:(DropboxUpload *)du completedUploadingFile:(NSString *)file {
    self.tableView.tableHeaderView = self.uploadHeadingView;
    self.uploadProgressView.progress = 1.0f;
    self.uploadLabel.text = [NSString stringWithFormat:@"Completed %@", [file lastPathComponent]];
    [self performSelector:@selector(hideUploadHeader) withObject:nil afterDelay:2.0f];
}

- (void)dropboxUpload:(DropboxUpload *)du failedToUploadFile:(NSString *)file withError:(NSError *)error {
    self.tableView.tableHeaderView = self.uploadHeadingView;
    self.uploadProgressView.progress = 1.0f;
    self.uploadLabel.text = [NSString stringWithFormat:@"Failed to upload %@", [file lastPathComponent]];
    [self performSelector:@selector(hideUploadHeader) withObject:nil afterDelay:2.0f];
}

- (void)dropboxUploadCompletedAllFiles:(DropboxUpload *)du {
    self.tableView.tableHeaderView = self.uploadHeadingView;
    self.uploadProgressView.progress = 1.0f;
    self.uploadLabel.text = nil;
    [self performSelector:@selector(hideUploadHeader) withObject:nil afterDelay:2.0f];
}

#pragma mark - Recording View Controller Delegate

- (void)recordingViewControllerCompletedWithSuccess:(RecordingViewController *)rvc {
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.mode = MBProgressHUDModeCustomView;
    hud.customView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"37x-Checkmark"]];
    hud.labelText = @"Video Created";
    [hud hide:YES afterDelay:2.0f];
}

#pragma mark - Dropbox

- (void)dropboxLoginHandled:(NSNotification *)note {
    [self updateDropboxButtonUI];
    [self refreshVideoFiles];
}

- (IBAction)dropboxLink:(id)sender {
    if ([[DBSession sharedSession] isLinked]) {
        [[DBSession sharedSession] unlinkAll];
        UIAlertView *av = [[UIAlertView alloc]
                           initWithTitle:@"Account Unlinked!" message:@"Your dropbox account has been unlinked"
                           delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
        [av show];
        [self updateDropboxButtonUI];
    } else {
        [[DBSession sharedSession] linkFromController:self];
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
	
    //	[DBRequest setNetworkRequestDelegate:self];
    
	if (errorMsg != nil) {
		[[[UIAlertView alloc]
          initWithTitle:@"Error Configuring Dropbox Session" message:errorMsg
          delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]
		 show];
	}
}

- (DBRestClient *)dbRestClient {
    if (![[DBSession sharedSession] isLinked]) {
        NSLog(@"Not creating rest client since db is not linked");
        return nil;
    }
    
    static DBRestClient *rc = nil;
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

static int outstandingRequests = 0;

- (void)networkRequestStarted {
	outstandingRequests++;
	if (outstandingRequests > 0) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
	}
}

- (void)networkRequestStopped {
	outstandingRequests--;
	if (outstandingRequests == 0) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	}
}


#pragma mark - DBRestClientDelegate

- (void)restClient:(DBRestClient*)client uploadedFile:(NSString*)destPath
              from:(NSString*)srcPath metadata:(DBMetadata*)metadata {
    
    NSLog(@"File uploaded successfully to path: %@", metadata.path);
    
    NSString *target = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/merged"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
    target = [target stringByAppendingPathComponent:[srcPath lastPathComponent]];
    [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath:target error:&error];
    if (error) {
        NSLog(@"%@", error);
        //abort();
    }
    self.fileToUploadPath = nil;
    [self refreshVideoFiles];
    
    //Use the source path to update the correct UI elements
    
//    [[NSFileManager defaultManager] removeItemAtPath:srcPath error:nil];
//    self.uploadingToDropbox = NO;
}

- (void)restClient:(DBRestClient*)client uploadFileFailedWithError:(NSError*)error {
    NSLog(@"File upload failed with error - %@", error);
//    self.uploadingToDropbox = NO;
}

- (void)restClient:(DBRestClient*)client uploadProgress:(CGFloat)progress
           forFile:(NSString*)destPath from:(NSString*)srcPath {
    self.title = [NSString stringWithFormat:@"Upload (%d%%)...", (int)progress * 100];
}

//Lets try chunked uploading and see if that is more robust


- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath fromUploadId:(NSString *)uploadId
          metadata:(DBMetadata *)metadata{
    
    
    NSString *target = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/merged"];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
    target = [target stringByAppendingPathComponent:[self.fileToUploadPath lastPathComponent]];
    [[NSFileManager defaultManager] moveItemAtPath:self.fileToUploadPath toPath:target error:&error];
    if (error) {
        NSLog(@"%@", error);
        //abort(); //Lets not abort, it can fail silently if it really has to on release
    }
    NSLog(@"File uploaded successfully to path: %@", metadata.path);
    self.fileToUploadPath = nil;
    self.uploadProgress = 0;
    [self refreshVideoFiles];

    
}

- (void)restClient:(DBRestClient *)client uploadFromUploadIdFailedWithError:(NSError *)error{
    NSLog(@"File upload failed with error - %@", error);
    //Try a couple more times
    if (error != nil && (self.uploadErrorCount < MAX_ERRORS_PER_CHUNK))
    {
        self.uploadErrorCount++;
        NSString* uploadId = [error.userInfo objectForKey:@"upload_id"];
        [self.dbRestClient uploadFile:[self.fileToUploadPath lastPathComponent] toPath:@"/" withParentRev:nil fromUploadId:uploadId];
        
    }
    else
    {
        //Cancels this upload and starts a new attempt
        self.fileToUploadPath = nil;
        [self refreshVideoFiles];
        
    }

    
}




- (void)restClient:(DBRestClient *)client uploadedFileChunk:(NSString *)uploadId newOffset:(unsigned long long)offset fromFile:(NSString *)localPath expires:(NSDate *)expiresDate{
    
    unsigned long long fileSize = [[[NSFileManager defaultManager]attributesOfItemAtPath:self.fileToUploadPath error:nil]fileSize];
    
    self.uploadErrorCount = 0;
    
    if (offset >= fileSize)
    {
        //Upload complete, commit the file.

        [self.dbRestClient uploadFile:[self.fileToUploadPath lastPathComponent] toPath:@"/" withParentRev:nil fromUploadId:uploadId];
        //self.fileToUploadPath = nil;
        //[self refreshVideoFiles];
    }
    else
    {
        //Send the next chunk and update the progress HUD.
        //self.progressHUD.progress = (float)((float)offset / (float)fileSize);
        self.uploadProgress = (float)((float)offset / (float)fileSize);
        NSLog(@"Uploading %f",  self.uploadProgress);
        [self.tableView reloadData];
        [self.dbRestClient uploadFileChunk:uploadId offset:offset fromPath:self.fileToUploadPath];
    }
}

- (void)restClient:(DBRestClient *)client uploadFileChunkFailedWithError:(NSError *)error
{
    NSLog(@"Chunk Upload Error");
    if (error != nil && (self.uploadErrorCount < MAX_ERRORS_PER_CHUNK))
    {
        self.uploadErrorCount++;
        NSString* uploadId = [error.userInfo objectForKey:@"upload_id"];
        unsigned long long offset = [[error.userInfo objectForKey:@"offset"]unsignedLongLongValue];
        [self.dbRestClient uploadFileChunk:uploadId offset:offset fromPath:self.fileToUploadPath];

    }
    else
    {
        //Cancels this upload and starts a new attempt
        self.fileToUploadPath = nil;
        [self refreshVideoFiles];
        
    }
}



#pragma mark - UIAlertViewDelegate methods

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (index != alertView.cancelButtonIndex) {
		[[DBSession sharedSession] linkUserId:self.relinkUserId fromController:self];
	}
	self.relinkUserId = nil;
}

#pragma mark - UI Updating

- (void)updateDropboxButtonUI {
    self.dropboxBarButtonItem.title = [[DBSession sharedSession] isLinked] ? @"Unlink Dropbox" : @"Link Dropbox";
}

- (void)refreshVideoFiles {
    NSLog(@"Refreshing Table");
    NSArray *docs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/merged"] error:nil];
//    NSArray *uploads = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/toUpload"] error:nil];
//    NSArray *fresh = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/creation"] error:nil];
    self.videoFiles = [docs mutableCopy];
    [self.videoFiles sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSString *s1 = obj1;
        NSString *s2 = obj2;
        return [s2 compare:s1];
    }];
//    self.toUploadFiles = [uploads mutableCopy];
//    self.freshlyCreated = [fresh mutableCopy];
    
//    if(self.fileToUploadPath == nil && [self.toUploadFiles count] >0 && [[NSUserDefaults standardUserDefaults] boolForKey:@"auto upload to dropbox"]){
//        NSString *target = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/toUpload"];
//        target = [target stringByAppendingPathComponent:[self.toUploadFiles objectAtIndex:0]];
//        NSLog(@"Uploading %@", target);
//        self.fileToUploadPath = target;
//        
//        //[self.dbRestClient uploadFile:[self.toUploadFiles objectAtIndex:0] toPath:@"/" withParentRev:nil fromPath:target];
//        //Chunking start
//        [self.dbRestClient uploadFileChunk:nil offset:0 fromPath:self.fileToUploadPath];
//        
//    }
    
    [self.tableView reloadData];
}

#pragma mark - Video Files Reading

- (void)videoRecordingCompleted:(NSNotification *)note {
//    self.canSkipReloadOnAppear = NO;
}

#pragma mark - Recording

//- (IBAction)startRecording:(id)sender {
//
//    //Do something pretty with the UI
//    //Lets set the animation on the record button
//    self.recordButton.imageView.animationImages = self.buttonAnimationArray;
//    self.recordButton.imageView.animationDuration = 1.5; //whatever you want (in seconds)
//    [self.recordButton.imageView startAnimating];
//    
//    [self.videoCapture startRecording];
//    [self startScreenLockTimer];
//    
//    if (!self.videoCapture.recordAudio) {
//        [[MMPDeepSleepPreventer sharedDeepSleepPreventer] startPreventSleep];
////        [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] startBackgrounder];
//    }
//    
//    
//}
//
//- (IBAction)stopRecording:(id)sender {
//    [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
////    [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] stopBackgrounder];
//    [self.videoCapture stopRecording];
//    [self stopScreenLockTimer];
//    [self.recordButton.imageView stopAnimating];
//
//    [self.recordButton setImage:[UIImage imageNamed:@"record.png"] forState:UIControlStateNormal];
//    
//    //[self refreshVideoFiles]; - This should be done when the combining returns. 
////    [self dismissViewControllerAnimated:YES completion:^{
////        [[NSNotificationCenter defaultCenter] postNotificationName:@"LeftVideoRecord" object:nil];
////    }];
//}

#pragma mark - Screen Lock Checking
//
//- (void)startScreenLockTimer {
//    self.screenLockCheckTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(screenLockCheckTick:) userInfo:nil repeats:YES];
//}
//
//- (void)stopScreenLockTimer {
//    [self.screenLockCheckTimer invalidate];
//    self.screenLockCheckTimer = nil;
//}
//
//- (void)screenLockCheckTick:(NSTimer *)timer {
//    BOOL current = [self isScreenLocked];
//    if (self.lastScreenLockStatus != current) {
//        self.lastScreenLockStatus = current;
//        if (self.lastScreenLockStatus) {
//            if (self.videoCapture.recordAudio) {
//                [[MMPDeepSleepPreventer sharedDeepSleepPreventer] startPreventSleep];
////                [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] startBackgrounder];
//            }
//            NSLog(@"Stopping video because screen lock detected");
//            NSString *p = [self.videoCapture stopRecordingReturnPath];
//             //This should be an async quque managed by the OS
//            //Do some auto dropbox upload stuff.
//            
//            
//            
//        } else {
//            if (self.videoCapture.recordAudio) {
//                [[MMPDeepSleepPreventer sharedDeepSleepPreventer] stopPreventSleep];
////                [[LocationBasedBackgrounder sharedLocationBasedBackgrounder] stopBackgrounder];
//            }
//            NSLog(@"Starting video because screen unlock detected");
//            [self.videoCapture startRecording];
//        }
//    }
//}
//
//- (BOOL)isScreenLocked {
//	void *sbserv = dlopen(SBSERVPATH, RTLD_LAZY);
//	void* (*SBGetScreenLockStatus)(mach_port_t* port, BOOL *lockStatus, BOOL *passcoded) = dlsym(sbserv, "SBGetScreenLockStatus");
//	BOOL ab, bb = NO;
//	
//    //Not working for some reason, always returning -64 : 0
//    //Will try on 4S when it charges.
//    
//	SBGetScreenLockStatus(self.sbPort, &ab, &bb);
//	NSLog(@"Locked = %d, Passcoded = %d", ab, bb);
//	dlclose(sbserv);
//	return ab;
//}

#pragma mark - Table view data source

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    //Lets combine the sections this way as the logic is tied to the sections.  
    return nil;
    
    switch (section) {
        case 0:
            return @"Videos";
        case 1:
            return @"To Process";
        default:
            return nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return self.videoFiles.count;
        case 1:
            return self.freshlyCreated.count;
        case 2:
            return self.toUploadFiles.count;
        default:
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
//    NSString *CellIdentifier = @"ToUploadCell";
    NSString *CellIdentifier = @"Cell";
    
    NSArray *ar = self.videoFiles;
//    switch (indexPath.section) {
//        case 0:
//            ar = self.videoFiles;
//            break;
//        case 1:
//            ar = self.freshlyCreated;
//            break;
//        case 2:
//            CellIdentifier = @"ProcessingCell";
//            ar = self.toUploadFiles;
//        default:
//            break;
//    }
    
    
    FileCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    NSString *name = [ar objectAtIndex:indexPath.row];
    cell.file = name;
    
    name = [name stringByDeletingPathExtension];
    
    NSDate *d = [NSDate dateWithTimeIntervalSinceReferenceDate:[name doubleValue]];
    cell.textLabel.text = [NSDateFormatter localizedStringFromDate:d dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    
//    if(self.fileToUploadPath != nil && indexPath.section == 1 && indexPath.row == 0){
//        
//        //An uploading file
//        cell.textLabel.text = [cell.textLabel.text stringByAppendingFormat:@" (%2.f %%)", self.uploadProgress*100];
//        
//    }
    
//    switch (indexPath.section) {
//        case 0:
//            //cell.dbImage.image = [UIImage imageNamed@"dbuploaded"];
//            break;
//        case 1:
//            //cell.dbImage.image = [UIImage imageNamed@"dbtoupload"];
//            break;
//            
//        default:
//            break;
//    }
    
    
//    cell.accessoryType = indexPath.section <= 1 && [[DBSession sharedSession] isLinked] ? UITableViewCellAccessoryDetailDisclosureButton : UITableViewCellAccessoryNone;
    
    static UIImage *simg = nil;
    static UIImage *simgHigh = nil;
    if (!simg) {
        simg = [UIImage imageNamed:@"socialShare"];
        simgHigh = [UIImage imageNamed:@"socialShareHighlight"];
    }
    
    UIButton *b = [[UIButton alloc] initWithFrame:CGRectMake(0.0f, 0.0f, cell.frame.size.height-10, cell.frame.size.height-10)];
    [b setImage:simg forState:UIControlStateNormal];
    [b setImage:simgHigh forState:UIControlStateHighlighted];
    cell.accessoryView = b;
    [b addTarget:self action:@selector(share:) forControlEvents:UIControlEventTouchUpInside];
    
    return cell;
}

- (IBAction)share:(id)sender {
    UIButton *b = sender;
    
    FileCell *cell = (FileCell *)[b superview];
    
    NSString *path = @"Documents/merged";
    path = [path stringByAppendingPathComponent:cell.file];
    path = [NSHomeDirectory() stringByAppendingPathComponent:path];
    
    NSURL *url = [NSURL fileURLWithPath:path];
    
    self.interactionController =
    [UIDocumentInteractionController interactionControllerWithURL:url];
    
    NSDate *d = [NSDate dateWithTimeIntervalSinceReferenceDate:[cell.file doubleValue]];
    NSString *ds = [NSDateFormatter localizedStringFromDate:d dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    
    self.interactionController.name = [NSString stringWithFormat:@"Video file from %@", ds];
    
    [self.interactionController presentOptionsMenuFromRect:b.frame inView:self.view animated:YES];
}


// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}


// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSMutableArray *mar;
        NSString *path = nil;//indexPath.section ? @"Documents/toUpload" : @"Documents";
        switch (indexPath.section) {
            case 0:
                path = @"Documents/merged";
                mar = self.videoFiles;
                break;
            case 1:
                path = @"Documents/toUpload";
                mar = self.toUploadFiles;
                break;
            case 2:
                path = @"Documents/creation";
                mar = self.freshlyCreated;
                break;
            default:
                break;
        }
        path = [path stringByAppendingPathComponent:[mar objectAtIndex:indexPath.row]];
        path = [NSHomeDirectory() stringByAppendingPathComponent:path];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [mar removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *ar;
    NSString *path = nil;//indexPath.section ? @"Documents/toUpload" : @"Documents";
    switch (indexPath.section) {
        case 0:
            path = @"Documents/merged";
            ar = self.videoFiles;
            break;
//        case 1:
//            path = @"Documents/toUpload";
//            ar = self.toUploadFiles;
//            break;
//        case 2: {
//            ar = self.freshlyCreated;
//            path = @"Documents/creation";
//            //Shouldnt need this now
//            
//            path = [path stringByAppendingPathComponent:[ar objectAtIndex:indexPath.row]];
//            path = [NSHomeDirectory() stringByAppendingPathComponent:path];
//            VideoAndAudioMerger *vaam = [VideoAndAudioMerger sharedVideoAndAudioMerger];
//            vaam.delegate = self;
//            [vaam processFilesInDirectory:path];
//            
//            return;
//        }
//            break;
        default:
            break;
    }
    path = [path stringByAppendingPathComponent:[ar objectAtIndex:indexPath.row]];
    path = [NSHomeDirectory() stringByAppendingPathComponent:path];
    
    MPMoviePlayerViewController *moviePlayerController = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:path]];
    //[moviePlayerController.moviePlayer  ]
//    NSError *setCategoryError = nil;
//    BOOL success = [[AVAudioSession sharedInstance]
//                    setCategory: AVAudioSessionCategoryPlayback
//                    error: &setCategoryError];
//    
//    if (!success) {
//        NSLog(@"This probably means that whatever else is playing audio isn't playing nice. ");
//    }
    [moviePlayerController.moviePlayer prepareToPlay];
    [self presentMoviePlayerViewControllerAnimated:moviePlayerController];
}
//
//- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
//    
//    NSArray *ar = indexPath.section ? self.toUploadFiles : self.videoFiles;
//    NSString *path;
//    switch (indexPath.section) {
//        case 0:
//            path = @"Documents/merged";
//            break;
//        case 1:
//            path = @"Documents/toUpload";
//            break;
//        case 2:
//            path = @"Documents/creation";
//            break;
//        default:
//            break;
//    }
//    path = [path stringByAppendingPathComponent:[ar objectAtIndex:indexPath.row]];
//    path = [NSHomeDirectory() stringByAppendingPathComponent:path];
//    NSURL *urlToShare = [NSURL fileURLWithPath:path isDirectory:NO];
//    
//    self.interactionController =
//                    [UIDocumentInteractionController interactionControllerWithURL:urlToShare];
//
//    [self.interactionController presentOptionsMenuFromRect:[tableView cellForRowAtIndexPath:indexPath].frame inView:self.view animated:YES];
//
//    
//    
//    /*
//    
//    
//    if (![self.navigationItem.title isEqualToString:@"Recordings"]) {
//        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Upload in Progress" message:@"A file is already uploading. Try again when upload is completed" delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
//        [av show];
//        return;
//    }
//    
//    if (![[DBSession sharedSession] isLinked]) {
//        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Dropbox Not Linked" message:@"App not linked to Dropbox, please try linking Dropbox before uploading a file" delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
//        [av show];
//        return;
//    }
//    
//    NSArray *ar = indexPath.section ? self.toUploadFiles : self.videoFiles;
//    NSString *path;
//    switch (indexPath.section) {
//        case 0:
//            path = @"Documents/merged";
//            break;
//        case 1:
//            path = @"Documents/toUpload";
//            break;
//        case 2:
//            path = @"Documents/creation";
//            break;
//        default:
//            break;
//    }
//    path = [path stringByAppendingPathComponent:[ar objectAtIndex:indexPath.row]];
//    path = [NSHomeDirectory() stringByAppendingPathComponent:path];
//    
//    self.fileToUploadPath = path;
//    
//    UIActionSheet *as = [[UIActionSheet alloc] initWithTitle:@"Upload File?" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Upload to Dropbox", nil];
//    [as showFromToolbar:self.navigationController.toolbar];
//    
////    NSString *upPath = [NSString stringWithFormat:@"/%@/", [UUID MACAddress]];
////    [self.dbRestClient uploadFile:[path lastPathComponent] toPath:@"/" withParentRev:nil fromPath:path];
//     
//     */
//}


#pragma mark - Dropbox Autouploader




#pragma mark - UIActionSheet Delegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    if ([title rangeOfString:@"upload" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [self.dbRestClient uploadFile:[self.fileToUploadPath lastPathComponent] toPath:@"/" withParentRev:nil fromPath:self.fileToUploadPath];
    }
}

@end
