//
//  POPAppDelegate.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/20/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPAppDelegate.h"
#import "POPDvdTracks.h"
#import "POPDvdTracksTableViewDataSource.h"
#import "POPDvd2Mp4.h"
#import "POPDvd.h"
#import "POPmp4v2dylibloader.h"

@implementation POPAppDelegate
{
	POPMp4DVDPage _currentPage;
	POPDvdTracks* _tracks;
	POPDvdTracksTableViewDataSource* _tracksTableViewDataSource;
	NSInteger _currentConvertTrackIndex;
	NSInteger _currentConvertTrackCount;
	POPDvd* _dvd;
}
- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self setCurrentPage:POPMp4DVDPageDVDDrop];
	_tracks = nil;
	_dvdPath = @"";
	_dvd2mp4 = nil;
	_dvd = nil;
	
	[POPmp4v2dylibloader loadMp4v2Lib:[[NSBundle mainBundle] pathForResource:@"libmp4v2.2" ofType:@"dylib"]];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

-(void)openDvdWithPath:(NSString*)path
{
	_dvdPath = path;
	if(_tracks != nil) _tracks = nil;
	
	_dvd = [[POPDvd alloc] initWithDevicePath:path];
	_tracks = [[POPDvdTracks alloc] initWithDictionary:[_dvd contents]];
	_tracksTableViewDataSource = [[POPDvdTracksTableViewDataSource alloc] initWithTracks:_tracks];
	[[self tracksBoxView] setTitle:[_tracks title]];
	[self setCurrentPage:POPMp4DVDPageTrackSelect];
}

-(void)dvdDragEnded:(NSString*)path
{
	//[self openDvdWithPath:@"/dev/disk2"];
	[self openDvdWithPath:path];
}

- (IBAction)cancelRipButtonClick:(id)sender
{
	if([[[self cancelRipButton] title] compare:@"Cancel"] == 0)
	{
		[[self cancelRipButton] setTitle:@"Close"];
		[_dvd2mp4 terminate];
	}
	else if([[[self cancelRipButton] title] compare:@"Close"] == 0)
	{
		[[self window] close];
	}
}

- (IBAction)helpClick:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/popmedic/mp4dvd#mp4dvd"]];
}

-(POPMp4DVDPage)currentPage
{
	return _currentPage;
}

- (IBAction)ripButtonClick:(id)sender
{
	NSSavePanel* savePanel	= [NSSavePanel savePanel];
	[savePanel setNameFieldStringValue:[_tracks title]];
	NSInteger res	= [savePanel runModal];
	if(res == NSOKButton)
	{
		_outputFileBasePath = [[savePanel URL] path];
		if([[_outputFileBasePath pathExtension] compare:@"mp4" options:NSCaseInsensitiveSearch] != 0)
		{
			_outputFileBasePath = [_outputFileBasePath stringByDeletingPathExtension];
		}
		[[self ripBoxView] setTitle:[_outputFileBasePath lastPathComponent]];
		
		_dvd2mp4 = [[POPDvd2Mp4 alloc] initWithTracks:_tracks
											  dvdPath:[_dvdPath stringByResolvingSymlinksInPath]
								   outputFileBasePath:_outputFileBasePath];
		[_dvd2mp4 setDelegate:self];
		[_dvd2mp4 launch];
		[self setCurrentPage:POPMp4DVDPageRipping];
	}
	savePanel = nil;
}
-(void)setCurrentPage:(POPMp4DVDPage)page
{
	if(page == POPMp4DVDPageDVDDrop)
	{
		[[self dropDVDImageView] setDelegate:(id<POPDropDVDImageViewDelegate>)self];
		
		[[self window]setContentView:[self dropDVDImageView]];
	}
	else if(page == POPMp4DVDPageTrackSelect)
	{
		[[self trackTableView] setDataSource:(id<NSTableViewDataSource>)_tracksTableViewDataSource];
		[[self trackTableView] reloadData];
		
		[[self window]setContentView:[self tracksBoxView]];
	}
	else if(page == POPMp4DVDPageRipping)
	{
		[[self window]setContentView:[self ripBoxView]];
	}
	_currentPage = page;
}

-(void) dvdRipStarted
{
	NSLog(@"Ripping Started.");
	@synchronized(self)
	{
		[[self currentProgressLabel] setStringValue:@"Ripping Started..."];
		[[self currentProgressIndicator] setDoubleValue:0.0];
		[[self tracksProgressLabel] setStringValue:[NSString stringWithFormat:@"Ripping: %@", _tracks.device]];
		[[self tracksProgressIndicator] setDoubleValue:0.0];
		[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Ripping: %@", _tracks.device]];
		[[self overallProgressIndicator] setDoubleValue:0.0];
//		[[self currentProgressLabel] display];
//		[[self currentProgressIndicator] display];
//		[[self tracksProgressLabel] display];
//		[[self tracksProgressIndicator] display];
//		[[self overallProgressLabel] display];
//		[[self overallProgressIndicator] display];
	}
}
-(void) converterStarted:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Converter Started. %li of %li", i, n);
	@synchronized(self)
	{
		_currentConvertTrackIndex = i;
		_currentConvertTrackCount = n;
		[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Converting track %li of %li.", i, n]];
		[[self tracksProgressLabel] setStringValue:[NSString stringWithFormat:@"Converting track %li of %li.", i, n]];
		[[self tracksProgressIndicator] setDoubleValue:(i/n)*100];
		[[self currentProgressIndicator] setDoubleValue:0.0];
//		[[self currentProgressLabel] display];
//		[[self currentProgressIndicator] display];
//		[[self tracksProgressLabel] display];
//		[[self tracksProgressIndicator] display];
		[[self currentProgressPercentLabel] setStringValue:@"0%"];
//		[[self currentProgressPercentLabel] display];
		[[self overallProgressPercentLabel] setStringValue:@"0%"];
//		[[self overallProgressPercentLabel] display];
		[[self tracksProgressPercentLabel] setStringValue:@"0%"];
//		[[self tracksProgressPercentLabel] display];
	}
}
-(void) stageStarted:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Stage Started. %li of %li", i, n);
	@synchronized(self)
	{
		if(i == 1)
		{
			[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Copying VOB file."]];
		}
		else if(i == 2)
		{
			[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Encoding to MP4 file. (%li/%li)", i, n]];
		}
		[[self currentProgressLabel] display];
	}
}
-(void) stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent
{
	volatile double overall;
	volatile double track;
	volatile double prcnt = percent;
	
	@synchronized(self)
	{
		track = (prcnt/(double)POPDvd2Mp4NumberOfStages)+(((double)stage/(double)POPDvd2Mp4NumberOfStages)*100.0 );
		overall = (track/(double)_currentConvertTrackCount)+((((double)_currentConvertTrackIndex-1.0)/(double)_currentConvertTrackCount)*100.0);
		@try
		{
			[[self currentProgressIndicator] setDoubleValue:prcnt];
			//[[self currentProgressPercentLabel] setStringValue:[NSString stringWithFormat:@"%0.2f%%", prcnt]];
			[[self tracksProgressIndicator] setDoubleValue:track];
			//[[self tracksProgressPercentLabel] setStringValue:[NSString stringWithFormat:@"%0.2f%%", track]];
			[[self overallProgressIndicator] setDoubleValue:overall];
			//[[self overallProgressPercentLabel] setStringValue:[NSString stringWithFormat:@"%0.2f%%", overall]];
		}
		@catch (NSException* e) {
			NSLog(@"Exception Caught, carry on my son: %@", e.description);
		}
	}
}
-(void) stageEnded:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Stage Ended. %li of %li", i, n);
}
-(void) converterEnded:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Converter Ended. %li of %li", i, n);
}
-(void) dvdRipEnded
{
	NSLog(@"Rip Ended.");
	
	//@synchronized(self)
	//{
		[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished"]];
		[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished."]];
		[[self tracksProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished."]];
		[[self tracksProgressIndicator] setDoubleValue:100.0];
		[[self overallProgressIndicator] setDoubleValue:100.0];
		[[self currentProgressIndicator] setDoubleValue:100.0];
//		[[self currentProgressLabel] display];
//		[[self currentProgressIndicator] display];
//		[[self overallProgressLabel] display];
//		[[self overallProgressIndicator] display];
		[[self cancelRipButton] setTitle:@"Close"];
//		[[self currentProgressPercentLabel] setStringValue:@"100%"];
//		[[self currentProgressPercentLabel] display];
//		[[self overallProgressPercentLabel] setStringValue:@"100%"];
//		[[self overallProgressPercentLabel] display];
//		[[self tracksProgressPercentLabel] setStringValue:@"100%"];
//		[[self tracksProgressPercentLabel] display];
	//}
}
@end
