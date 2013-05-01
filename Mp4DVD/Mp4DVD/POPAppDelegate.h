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
#import "POPDvdCopy.h"

typedef enum
{
	POPMp4DVDPageDVDDrop=1,
	POPMp4DVDPageTrackSelect=2,
	POPMp4DVDPageRipping=3
} POPMp4DVDPage;

@interface POPAppDelegate : NSObject <NSApplicationDelegate, POPDvd2Mp4Delegate, POPDvdCopyDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet POPDropDVDImageView *dropDVDImageView;
@property (assign) IBOutlet NSTableView *trackTableView;
@property (assign) IBOutlet NSBox *tracksBoxView;
@property (assign) IBOutlet NSButton *ripButton;
@property (assign) IBOutlet NSBox *ripBoxView;
@property (assign) IBOutlet NSButton *cancelRipButton;
@property (assign) IBOutlet NSTextField *currentProgressLabel;
@property (assign) IBOutlet NSTextField *currentPercentLabel;
@property (assign) IBOutlet NSProgressIndicator *currentProgressIndicator;
@property (assign) IBOutlet NSTextField *overallProgressLabel;
@property (assign) IBOutlet NSTextField *overallPercentLabel;
@property (assign) IBOutlet NSProgressIndicator *overallProgressIndicator;
@property (assign) IBOutlet NSProgressIndicator *tracksProgressIndicator;
@property (assign) IBOutlet NSTextField *tracksProgressLabel;
@property (assign) IBOutlet NSTextField *tracksPercentLabel;
@property (assign) IBOutlet NSTextField *elapsedTimeLabel;
@property (assign) IBOutlet NSTextField *remainingTimeLabel;

@property (assign) IBOutlet NSWindow *prefsWindow;
@property (assign) IBOutlet NSButton *vobCopyOnlyBtn;
@property (assign) IBOutlet NSButton *mirrorDVDBtn;

@property (getter=currentPage,setter=setCurrentPage:) POPMp4DVDPage currentPage;
@property (assign) NSString* outputFileBasePath;
@property (assign) NSString* dvdPath;
@property (assign) POPDvd2Mp4* dvd2mp4;
@property (assign) POPDvdCopy* dvdCopy;

- (IBAction)ripButtonClick:(id)sender;
- (IBAction)cancelRipButtonClick:(id)sender;
- (IBAction)helpClick:(id)sender;
- (IBAction)prefsClick:(id)sender;
- (IBAction)prefsVobCopyOnlyClick:(id)sender;
- (IBAction)prefsMirrorDVDClick:(id)sender;
- (IBAction)prefsCloseClick:(id)sender;

-(void)dvdDragEnded:(NSString*)path;

@end
