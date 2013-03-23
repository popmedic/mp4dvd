//
//  POPAppDelegate.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/20/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPAppDelegate.h"
#import "POPDvdTracks.h"
#import "POPDvdTracksViewController.h"
#import "POPDvd2Mp4.h"

@implementation POPAppDelegate
{
	POPMp4DVDPage _currentPage;
	POPDvdTracks* _tracks;
	POPDvdTracksViewController* _tracksViewController;
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
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

-(void)openDvdWithPath:(NSString*)path
{
	_dvdPath = path;
	if(_tracks != nil) _tracks = nil;
	_tracks = [POPDvdTracks dvdTracksFromDvdPath:path];
	_tracksViewController = [[POPDvdTracksViewController alloc] initWithTracks:_tracks];
	[[self tracksBoxView] setTitle:[_tracks title]];
	[self setCurrentPage:POPMp4DVDPageTrackSelect];
}

-(void)dvdDragEnded:(NSString*)path
{
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
											  dvdPath:_dvdPath
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
		
		[[self dropDVDImageView] setHidden:NO];
		[[self tracksBoxView] setHidden:YES];
		[[self ripBoxView] setHidden:YES];
	}
	else if(page == POPMp4DVDPageTrackSelect)
	{
		[[self trackTableView] setDataSource:(id<NSTableViewDataSource>)_tracksViewController];
		[[self trackTableView] reloadData];
		
		[[self dropDVDImageView] setHidden:YES];
		[[self tracksBoxView] setHidden:NO];
		[[self ripBoxView] setHidden:YES];
	}
	else if(page == POPMp4DVDPageRipping)
	{
		[[self dropDVDImageView] setHidden:YES];
		[[self tracksBoxView] setHidden:YES];
		[[self ripBoxView] setHidden:NO];
	}
	_currentPage = page;
}

-(void) dvdRipStarted
{
	NSLog(@"Ripping Started.");
	[[self currentProgressLabel] setStringValue:@"Ripping Started..."];
	[[self currentProgressIndicator] setDoubleValue:0.0];
	[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Ripping: %@", _tracks.device]];
	[[self overallProgressIndicator] setDoubleValue:0.0];
	[[self currentProgressLabel] display];
	[[self currentProgressIndicator] display];
	[[self overallProgressLabel] display];
	[[self overallProgressIndicator] display];
}
-(void) converterStarted:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Converter Started. %li of %li", i, n);
	[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Converting track %li of %li.", i, n]];
	[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Converting track %li of %li.", i, n]];
	[[self overallProgressIndicator] setDoubleValue:(i/n)*100];
	[[self currentProgressIndicator] setDoubleValue:0.0];
	[[self currentProgressLabel] display];
	[[self currentProgressIndicator] display];
	[[self overallProgressLabel] display];
	[[self overallProgressIndicator] display];
}
-(void) stageStarted:(NSInteger)i Of:(NSInteger)n
{
	NSLog(@"Stage Started. %li of %li", i, n);
	if(i == 1)
	{
		[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Copying VOB file. (%li/%li)", i, n]];
	}
	else if(i == 2)
	{
		[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Concatenating VOB files. (%li/%li)", i, n]];
	}
	else if(i == 3)
	{
		[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Encoding to MP4 file. (%li/%li)", i, n]];
	}
	[[self currentProgressLabel] display];
}
-(void) stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent
{
	double overall;
	if(stage != 0)
		overall = (percent/3.0)+(((float)stage/3.0)*100.0);
	else
		overall = (percent/3.0);//percent*(((float)stage+1.0)/3.0);
	//	NSLog(@"%f/3.0 = %f * %f = %f",(float)stage, t, percent, overall);
	/*if(percent > 0)
	{
		overall = (((double)percent/3.0)*(double)stage);
	}
	else
	{
		overall = ((double)stage/3.0)*(double)(stage-1);
	}*/
	[[self currentProgressIndicator] setDoubleValue:percent];
	[[self overallProgressIndicator] setDoubleValue:overall];
	[[self currentProgressIndicator] display];
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
	[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished"]];
	[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished."]];
	[[self overallProgressIndicator] setDoubleValue:100.0];
	[[self currentProgressIndicator] setDoubleValue:100.0];
	[[self currentProgressLabel] display];
	[[self currentProgressIndicator] display];
	[[self overallProgressLabel] display];
	[[self overallProgressIndicator] display];
}
@end
