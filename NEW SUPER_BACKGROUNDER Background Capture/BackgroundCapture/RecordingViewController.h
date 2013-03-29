//
//  RecordingViewController.h
//  BackgroundCapture
//
//  Created by marek on 04/03/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface RecordingViewController : UIViewController

@property (weak) id delegate;

@end

@protocol RecordingViewControllerDelegate <NSObject>

- (void)recordingViewControllerCompletedWithSuccess:(RecordingViewController *)rvc;
-(void)cancelRecording;
@end