//
//  POPAppDelegate.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/20/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "POPDropDVDImageView.h"
#import "POPDvd2Mp4.h"

typedef enum
{
	POPMp4DVDPageDVDDrop=1,
	POPMp4DVDPageTrackSelect=2,
	POPMp4DVDPageRipping=3
} POPMp4DVDPage;

@interface POPAppDelegate : NSObject <NSApplicationDelegate, POPDvd2Mp4Delegate>

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet POPDropDVDImageView *dropDVDImageView;
@property (assign) IBOutlet NSTableView *trackTableView;
@property (assign) IBOutlet NSBox *tracksBoxView;
@property (assign) IBOutlet NSButton *ripButton;
@property (assign) IBOutlet NSBox *ripBoxView;
@property (assign) IBOutlet NSButton *cancelRipButton;
@property (assign) IBOutlet NSTextField *currentProgressLabel;
@property (assign) IBOutlet NSProgressIndicator *currentProgressIndicator;
@property (assign) IBOutlet NSTextField *overallProgressLabel;
@property (assign) IBOutlet NSProgressIndicator *overallProgressIndicator;

@property (getter=currentPage,setter=setCurrentPage:) POPMp4DVDPage currentPage;
@property (retain) NSString* outputFileBasePath;
@property (retain) NSString* dvdPath;
@property (retain, strong) POPDvd2Mp4* dvd2mp4;

- (IBAction)ripButtonClick:(id)sender;
- (IBAction)cancelRipButtonClick:(id)sender;

-(void)dvdDragEnded:(NSString*)path;

@end
