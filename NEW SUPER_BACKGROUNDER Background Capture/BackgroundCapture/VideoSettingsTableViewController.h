//
//  VideoSettingsTableViewController.h
//  BackgroundCapture
//
//  Created by marek on 01/02/2013.
//  Copyright (c) 2013 BazDonMav. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface VideoSettingsTableViewController : UITableViewController{
    
    IBOutlet UITableView *tbv;
}

@property (weak) id delegate;

@end

@protocol VideoSettingsTableViewControllerDelegate <NSObject>

- (void)videoSettingsTableViewControllerCreatedVideo:(VideoSettingsTableViewController *)vstvc;

@end