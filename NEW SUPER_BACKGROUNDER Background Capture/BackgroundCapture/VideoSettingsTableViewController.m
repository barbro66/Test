//
//  VideoSettingsTableViewController.m
//  BackgroundCapture
//
//  Created by marek on 01/02/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import "VideoSettingsTableViewController.h"
#import "VideoCapture.h"
#import "VideoAndAudioMerger.h"
#import "RecordingViewController.h"

@interface VideoSettingsTableViewController ()

@property (weak, nonatomic) IBOutlet UISlider *fpsSlider;
@property (weak, nonatomic) IBOutlet UISlider *kbpsSlider;

@property (weak, nonatomic) IBOutlet UILabel *fpsLabel;
@property (weak, nonatomic) IBOutlet UILabel *kbpsLabel;

@property (weak, nonatomic) IBOutlet UISwitch *recordAudioSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *splitVideoOnLockSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *autoDropboxUploadSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *cellularUploadSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *deleteUploadedSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *uploadPoweredSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *halveVideoSizeSwitch;
@property (weak, nonatomic) IBOutlet UISegmentedControl *audioQualitySeg;

@property (weak, nonatomic) IBOutlet UITableViewCell *dropBoxAutouploadCell;
@property (weak, nonatomic) IBOutlet UITableViewCell *cellularUploadCell;
@property (weak, nonatomic) IBOutlet UITableViewCell *deleteAfterUploadCell;
@property (weak, nonatomic) IBOutlet UITableViewCell *uploadPoweredCell;
@property (weak, nonatomic) IBOutlet UIButton *dropboxButton;

@property (strong) NSString *relinkUserId;
@property BOOL userWarnedOfRelink;

@property (strong) VideoCapture *videoCapture;

@end

@implementation VideoSettingsTableViewController

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
    
    self.videoCapture = [VideoCapture sharedVideoCapture];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dropboxLoginHandled:) name:@"DropboxLoginHandled" object:nil];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateFpsLabel];
    [self updateKbpsLabel];
    [self updateQualitySeg];
    
    self.fpsSlider.value = self.videoCapture.fps;
    self.kbpsSlider.value = self.videoCapture.kbps / 100;
    
    self.recordAudioSwitch.on = self.videoCapture.recordAudio;
    self.halveVideoSizeSwitch.on = self.videoCapture.halveVideoSize;
    [self setDBUI];
    [tbv reloadData];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"RecordSegue"]) {
        RecordingViewController *rvc = segue.destinationViewController;
        rvc.delegate = self;
    }
}

#pragma mark - UI Updating

- (void)updateFpsLabel {
    self.fpsLabel.text = [NSString stringWithFormat:@"%d fps", self.videoCapture.fps];
}

- (void)updateKbpsLabel {
    self.kbpsLabel.text = [NSString stringWithFormat:@"%d kbps", self.videoCapture.kbps];
}

-(void)updateQualitySeg {
    switch (self.videoCapture.audioRate) {
        case 11025:
            self.audioQualitySeg.selectedSegmentIndex = 0;
            break;
        case 22050:
            self.audioQualitySeg.selectedSegmentIndex = 1;
            break;
        case 44100:
            self.audioQualitySeg.selectedSegmentIndex = 2;
            break;
        default:
            self.videoCapture.audioRate = 44100;
            self.audioQualitySeg.selectedSegmentIndex = 2;
            break;
    }
}

#pragma mark - Actions

- (IBAction)cancel:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)fpsSliderValueChanged:(id)sender {
    UISlider *s = sender;
    int fps = s.value;
    self.videoCapture.fps = fps;
    [self updateFpsLabel];
}

- (IBAction)kbpsSliderValueChanged:(id)sender {
    UISlider *s = sender;
    NSLog(@"%f", s.value);
    int k = s.value;
    k *= 100;
    self.videoCapture.kbps = k;
    [self updateKbpsLabel];
}

- (IBAction)recordAudioSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.recordAudio = s.on;
}

- (IBAction)autoDropboxUploadSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.dropboxAutoUpload = s.on;
}

- (IBAction)cellularUploadSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.cellularUpload = !s.on;
    self.videoCapture.uploadPowered = !s.on;
}

- (IBAction)deleteUploadedSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.deleteUploaded = s.on;
}

- (IBAction)uploadPoweredSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.uploadPowered = s.on;
}


- (IBAction)halveVideoSizeSwitchToggled:(id)sender {
    UISwitch *s = sender;
    self.videoCapture.halveVideoSize = s.on;
}

- (IBAction)audioQualitySegChanged:(id)sender{
    UISegmentedControl *s = sender;
    switch (s.selectedSegmentIndex) {
        case 0:
            self.videoCapture.audioRate = 11025;
            break;
        case 1:
            self.videoCapture.audioRate = 22050;
            break;
        case 2:
        default:
            self.videoCapture.audioRate = 44100;
            break;
    }
}


#pragma mark - Dropbox

-(void)setDBUI{
    if([[DBSession sharedSession] isLinked]){
        self.dropBoxAutouploadCell.userInteractionEnabled = YES;
        self.dropBoxAutouploadCell.alpha = 1.0;
        self.dropBoxAutouploadCell.backgroundColor = [UIColor whiteColor];
        
        self.cellularUploadCell.userInteractionEnabled = YES;
        self.cellularUploadCell.alpha = 1.0;
        self.cellularUploadCell.backgroundColor = [UIColor whiteColor];
        
        self.deleteAfterUploadCell.userInteractionEnabled = YES;
        self.deleteAfterUploadCell.alpha = 1.0;
        self.deleteAfterUploadCell.backgroundColor = [UIColor whiteColor];
        
       /* self.uploadPoweredCell.userInteractionEnabled = YES;
        self.uploadPoweredCell.alpha = 1.0;
        self.uploadPoweredCell.backgroundColor = [UIColor whiteColor];*/
        
        tbv.sectionFooterHeight = 15.0;
        
    }else{
        self.dropBoxAutouploadCell.userInteractionEnabled = YES;
        self.dropBoxAutouploadCell.alpha = 0.5;
        self.dropBoxAutouploadCell.backgroundColor = [UIColor grayColor];
        self.videoCapture.dropboxAutoUpload = NO;
        
        self.cellularUploadCell.userInteractionEnabled = YES;
        self.cellularUploadCell.alpha = 0.5;
        self.cellularUploadCell.backgroundColor = [UIColor grayColor];
        self.videoCapture.cellularUpload = NO;
        
        self.deleteAfterUploadCell.userInteractionEnabled = YES;
        self.deleteAfterUploadCell.alpha = 0.5;
        self.deleteAfterUploadCell.backgroundColor = [UIColor grayColor];
        self.videoCapture.deleteUploaded = NO;
        
       /* self.uploadPoweredCell.userInteractionEnabled = YES;
        self.uploadPoweredCell.alpha = 0.5;
        self.uploadPoweredCell.backgroundColor = [UIColor grayColor];
        self.videoCapture.uploadPowered = NO;*/
        tbv.sectionFooterHeight = 0.0;
    }
    
    self.autoDropboxUploadSwitch.on = self.videoCapture.dropboxAutoUpload;
    self.cellularUploadSwitch.on = !self.videoCapture.cellularUpload;
    self.deleteUploadedSwitch.on = self.videoCapture.deleteUploaded;
    //self.uploadPoweredSwitch.on = self.videoCapture.uploadPowered;
    
    [self.dropboxButton setTitle:[[DBSession sharedSession] isLinked] ? @"Unlink Dropbox" : @"Link Dropbox" forState:UIControlStateNormal];
    [self.tableView reloadData];
}

- (void)dropboxLoginHandled:(NSNotification *)note {
    [self setDBUI];
    [self.tableView reloadData];
    [tbv reloadData];
}

- (IBAction)dropboxLink:(id)sender {
    if ([[DBSession sharedSession] isLinked]) {
        [[DBSession sharedSession] unlinkAll];
        UIAlertView *av = [[UIAlertView alloc]
                           initWithTitle:@"Account Unlinked!" message:@"Your dropbox account has been unlinked"
                           delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil];
        [av show];
    } else {
        [[DBSession sharedSession] linkFromController:self];
        [tbv reloadData];
    }
    [self setDBUI];
}

//- (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session userId:(NSString *)userId {
//	self.relinkUserId = userId;
//    if (!self.userWarnedOfRelink) {
//        self.userWarnedOfRelink = YES;
//        [[[UIAlertView alloc]
//          initWithTitle:@"Dropbox Session Ended" message:@"Do you want to relink?" delegate:self
//          cancelButtonTitle:@"Cancel" otherButtonTitles:@"Relink", nil]
//         show];
//    }
//    [self setDBUI];
//}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
	if (index != alertView.cancelButtonIndex) {
		[[DBSession sharedSession] linkUserId:self.relinkUserId fromController:self];
	}
	self.relinkUserId = nil;
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return 5;
        case 1:
            return [[DBSession sharedSession] isLinked] ? 4 : 1;
        default:
            return 0;
    }
}

-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section{
    
    switch (section) {
        case 0:
            return 5;
        case 1:
            return [[DBSession sharedSession] isLinked] ? 120 : 0;
        default:
            return 0;
    }
    
    
}
//
//- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
//{
//    static NSString *CellIdentifier = @"Cell";
//    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
//    
//    // Configure the cell...
//    
//    return cell;
//}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

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
    // Navigation logic may go here. Create and push another view controller.
    /*
     <#DetailViewController#> *detailViewController = [[<#DetailViewController#> alloc] initWithNibName:@"<#Nib name#>" bundle:nil];
     // ...
     // Pass the selected object to the new view controller.
     [self.navigationController pushViewController:detailViewController animated:YES];
     */
}

@end
