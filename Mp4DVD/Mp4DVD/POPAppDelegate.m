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
#import "POPDvd.h"
#import "POPmp4v2dylibloader.h"
#import "POPTimeConverter.h"

@implementation POPAppDelegate
{
	POPMp4DVDPage _currentPage;
	POPDvdTracks* _tracks;
	POPDvdTracksTableViewDataSource* _tracksTableViewDataSource;
	NSInteger _currentConvertTrackIndex;
	NSInteger _currentConvertTrackCount;
	POPDvd* _dvd;
	NSTimer* _updateTimer;
	float _copyAndConvertElapsedSeconds;
	NSTimer* _mirrorTimer;
	float _mirrorElapsedSeconds;
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
	
	NSInteger chptrFileCreateState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"chptrFileCreateState"] integerValue];
	[[self chptrFileCreateBtn] setState:chptrFileCreateState];
	
	NSInteger vobCopyOnlyState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"vobCopyOnlyState"] integerValue];
	[[self vobCopyOnlyBtn] setState:vobCopyOnlyState];
	if(vobCopyOnlyState == NSOnState)
	{
		[[self chptrFileCreateBtn] setEnabled:YES];
	}
	else
	{
		[[self chptrFileCreateBtn] setEnabled:NO];
	}
	
	NSInteger mirrorDVDState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"mirrorDVDState"] integerValue];
	[[self mirrorDVDBtn] setState:mirrorDVDState];
	if(mirrorDVDState == NSOnState)
	{
		[[self vobCopyOnlyBtn] setEnabled:NO];
		[[self chptrFileCreateBtn] setEnabled:NO];
		[[self trackTableView] setEnabled:NO];
	}
	
	[POPmp4v2dylibloader loadMp4v2Lib:[[NSBundle mainBundle] pathForResource:@"libmp4v2.2" ofType:@"dylib"]];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

#pragma mark Property Getter/Setters

-(POPMp4DVDPage)currentPage
{
	return _currentPage;
}

-(void)setCurrentPage:(POPMp4DVDPage)page
{
	if(page == POPMp4DVDPageDVDDrop)
	{
		[[self dropDVDImageView] setDelegate:(id<POPDropDVDImageViewDelegate>)self];
		
		[[self window] setContentView:[self dropDVDImageView]];
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

#pragma mark helpers

-(void)openDvdWithPath:(NSString*)path
{
	_dvdPath = path;
	
	if(_dvd != nil) _dvd = nil;
	if(_tracks != nil) _tracks = nil;
	if(_tracksTableViewDataSource != nil) _tracksTableViewDataSource = nil;
	
	_dvd = [[POPDvd alloc] initWithDevicePath:path open:YES];
	_tracks = [[POPDvdTracks alloc] initWithDictionary:[_dvd contents]];
	_tracksTableViewDataSource = [[POPDvdTracksTableViewDataSource alloc] initWithTracks:_tracks];
	
	[[self tracksBoxView] setTitle:[_tracks title]];
	[self setCurrentPage:POPMp4DVDPageTrackSelect];
}

#pragma mark Menu Item Actions

- (IBAction)helpClick:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/popmedic/mp4dvd#mp4dvd"]];
}

- (IBAction)prefsClick:(id)sender
{
	[[self prefsWindow] setIsVisible:YES];
}

#pragma mark Button Actions

- (IBAction)cancelRipButtonClick:(id)sender
{
	if([[[self cancelRipButton] title] compare:@"Cancel"] == 0)
	{
		[[self cancelRipButton] setEnabled:NO];
		[[self cancelRipButton] display];
		NSInteger mirrorDVDState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"mirrorDVDState"] integerValue];
		if(mirrorDVDState == NSOnState)
		{
			[_dvdCopy terminate];
		}
		else
		{
			[_dvd2mp4 terminate];
		}
	}
	else if([[[self cancelRipButton] title] compare:@"Close"] == 0)
	{
		[[self window] close];
		//[self setCurrentPage:POPMp4DVDPageDVDDrop];
	}
}

- (IBAction)ripButtonClick:(id)sender
{
	NSSavePanel* savePanel	= [NSSavePanel savePanel];
	[savePanel setNameFieldStringValue:[[_tracks title] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	
	[[self ripButton] setEnabled:NO];
	
	//if we are just mirroring the DVD, or just copying a vob...
	NSInteger mirrorDVDState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"mirrorDVDState"] integerValue];
	NSInteger vobCopyOnlyState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"vobCopyOnlyState"] integerValue];
	if(mirrorDVDState != NSOnState)
	{
		if(vobCopyOnlyState == NSOnState)
		{
			[savePanel setAllowedFileTypes:[NSArray arrayWithObjects:@"VOB", nil]];
		}
		else
		{
			[savePanel setAllowedFileTypes:[NSArray arrayWithObjects:@"mp4", nil]];
		}
	}
	NSInteger res	= [savePanel runModal];
	if(res == NSOKButton)
	{
		_outputFileBasePath = [[savePanel URL] path];
		if([[_outputFileBasePath pathExtension] compare:@"mp4" options:NSCaseInsensitiveSearch] == 0 ||
		   [[_outputFileBasePath pathExtension] compare:@"vob" options:NSCaseInsensitiveSearch] == 0 )
		{
			_outputFileBasePath = [_outputFileBasePath stringByDeletingPathExtension];
		}
		[[self ripBoxView] setTitle:[_outputFileBasePath lastPathComponent]];
		if(mirrorDVDState != NSOnState)
		{
			_dvd2mp4 = [[POPDvd2Mp4 alloc] initWithTracks:_tracks
												  dvdPath:[_dvdPath stringByResolvingSymlinksInPath]
									   outputFileBasePath:_outputFileBasePath];
			[_dvd2mp4 setDelegate:self];
			[_dvd2mp4 launch];
		}
		else
		{
			_dvdCopy = [[POPDvdCopy alloc] initWithDevicePath:[self dvdPath]];
			[_dvdCopy setDelegate:self];
			[_dvdCopy launchWithOutputPath:[_outputFileBasePath copy]];
		}
	}
	
	[[self ripButton] setEnabled:YES];
	
	savePanel = nil;
}

#pragma mark Preferences actions

- (IBAction)prefsVobCopyOnlyClick:(id)sender
{
	NSInteger vobCopyOnlyState = [(NSButton*)sender state];
	if(vobCopyOnlyState == NSOnState)
	{
		[[self chptrFileCreateBtn] setEnabled:YES];
	}
	else
	{
		[[self chptrFileCreateBtn] setEnabled:NO];
	}
	[[NSUserDefaults standardUserDefaults] setInteger:vobCopyOnlyState forKey:@"vobCopyOnlyState"];
}

- (IBAction)prefsMirrorDVDClick:(id)sender
{
	
	NSInteger mirrorDVDState = [(NSButton*)sender state];
	if(mirrorDVDState == NSOnState)
	{
		[[self vobCopyOnlyBtn] setEnabled:NO];
		[[self chptrFileCreateBtn] setEnabled:NO];
		[[self trackTableView] setEnabled:NO];
	}
	else
	{
		[[self vobCopyOnlyBtn] setEnabled:YES];
		NSInteger vobCopyOnlyState = [[NSUserDefaults standardUserDefaults] integerForKey:@"vobCopyOnlyState"];
		if(vobCopyOnlyState == NSOnState)
		{
			[[self chptrFileCreateBtn] setEnabled:YES];
		}
		else
		{
			[[self chptrFileCreateBtn] setEnabled:NO];
		}
		[[self trackTableView] setEnabled:YES];
	}
	[[NSUserDefaults standardUserDefaults] setInteger:mirrorDVDState forKey:@"mirrorDVDState"];
}

- (IBAction)prefsChptrFileCreateClick:(id)sender
{
	NSInteger chptrFileCreateState = [(NSButton*)sender state];
	[[NSUserDefaults standardUserDefaults] setInteger:chptrFileCreateState forKey:@"chptrFileCreateState"];
}

- (IBAction)prefsCloseClick:(id)sender
{
	[[self prefsWindow] setIsVisible:NO];
}

#pragma mark POPDropDVDImageViewDelegate

-(void)dvdDragEnded:(NSString*)path
{
	//[self openDvdWithPath:@"/dev/disk2"];
	[self openDvdWithPath:path];
}

#pragma mark Timer functions for updateCopyAndConvertView
-(void)startUpdateCopyAndConvertTimer
{
	_copyAndConvertElapsedSeconds = 0.0;
	_updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateCopyAndConvertView) userInfo:nil repeats:YES];
}

-(void)endUpdateCopyAndConvertTimer
{
	[_updateTimer invalidate];
	[[self remainingTimeLabel] setStringValue:@"~00:00:00.00"];
}

-(void)updateCopyAndConvertView
{
	double percent = [[self currentProgressIndicator] doubleValue];
	double track = [[self tracksProgressIndicator] doubleValue];
	double overall = [[self overallProgressIndicator] doubleValue];
	
	_copyAndConvertElapsedSeconds++;
	double percent_per_second = overall / _copyAndConvertElapsedSeconds;
	double remaining_percent = 100.0 - overall;
	float remaining_seconds = remaining_percent / percent_per_second;
	
	NSString* elapsedTimeStr = [POPTimeConverter timeStringFromSecs:_copyAndConvertElapsedSeconds];
	elapsedTimeStr = [elapsedTimeStr substringToIndex:[elapsedTimeStr rangeOfString:@"."].location];
	[[self elapsedTimeLabel] setStringValue:elapsedTimeStr];
	
	NSString* remainingTimeStr = [NSString stringWithFormat:@"~%@",[POPTimeConverter timeStringFromSecs:remaining_seconds]];
	remainingTimeStr = [remainingTimeStr substringToIndex:[remainingTimeStr rangeOfString:@"."].location];
	[[self remainingTimeLabel] setStringValue:remainingTimeStr];
	
	[[self currentPercentLabel] setStringValue:[NSString stringWithFormat:@"%.2f%%", percent]];
	[[self tracksPercentLabel] setStringValue:[NSString stringWithFormat:@"%.2f%%", track]];
	[[self overallPercentLabel] setStringValue:[NSString stringWithFormat:@"%.2f%%", overall]];
}

#pragma mark Timer functions for updateMirrorView
-(void)startUpdateMirrorTimer
{
	_mirrorElapsedSeconds = 0.0;
	_mirrorTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateMirrorView) userInfo:nil repeats:YES];
}

-(void)endUpdateMirrorTimer
{
	[_mirrorTimer invalidate];
	[[self remainingTimeLabel] setStringValue:@"~00:00:00.00"];
}

-(void)updateMirrorView
{
	float percent = [[self currentProgressIndicator] doubleValue];
	
	_mirrorElapsedSeconds++;
	float percent_per_second = percent / _mirrorElapsedSeconds;
	float remaining_percent = 100.0 - percent;
	float remaining_seconds = remaining_percent / percent_per_second;
	
	NSString* elapsedTimeStr = [POPTimeConverter timeStringFromSecs:_mirrorElapsedSeconds];
	elapsedTimeStr = [elapsedTimeStr substringToIndex:[elapsedTimeStr rangeOfString:@"."].location];
	[[self elapsedTimeLabel] setStringValue:elapsedTimeStr];
	
	NSString* remainingTimeStr = [NSString stringWithFormat:@"~%@",[POPTimeConverter timeStringFromSecs:remaining_seconds]];
	remainingTimeStr = [remainingTimeStr substringToIndex:[remainingTimeStr rangeOfString:@"."].location];
	[[self remainingTimeLabel] setStringValue:remainingTimeStr];
	
	[[self currentPercentLabel] setStringValue:[NSString stringWithFormat:@"%.2f%%", percent]];
}

#pragma mark POPDvd2Mp4Delegate

-(void) dvdRipStarted
{
	NSLog(@"Ripping Started.");
	[[self currentProgressLabel] setStringValue:@"Ripping Started..."];
	[[self currentProgressIndicator] setDoubleValue:0.0];
	[[self currentPercentLabel] setStringValue:@"0.00%"];
	[[self tracksProgressLabel] setStringValue:[NSString stringWithFormat:@"Ripping: %@", _tracks.device]];
	[[self tracksProgressIndicator] setDoubleValue:0.0];
	[[self tracksPercentLabel] setStringValue:@"0.00%"];
	[[self overallProgressLabel] setStringValue:[NSString stringWithFormat:@"Ripping: %@", _tracks.device]];
	[[self overallProgressIndicator] setDoubleValue:0.0];
	[[self overallPercentLabel] setStringValue:@"0.00%"];
	[self setCurrentPage:POPMp4DVDPageRipping];
	[[self window] display];
	[self startUpdateCopyAndConvertTimer];
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
			[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Encoding to MP4 file."]];
		}
	}
}
-(void) stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent
{
	double overall;
	double track;
	NSInteger vobCopyOnlyState = [[[NSUserDefaults standardUserDefaults] objectForKey:@"vobCopyOnlyState"] integerValue];
	if(vobCopyOnlyState == NSOnState)
	{
		track = percent;
		overall = (track/(double)_currentConvertTrackCount)+((((double)_currentConvertTrackIndex-1.0)/(double)_currentConvertTrackCount)*100.0);
	}
	else
	{
		track = (percent/(double)POPDvd2Mp4NumberOfStages)+(((double)stage/(double)POPDvd2Mp4NumberOfStages)*100.0 );
		overall = (track/(double)_currentConvertTrackCount)+((((double)_currentConvertTrackIndex-1.0)/(double)_currentConvertTrackCount)*100.0);
	}
	[[self currentProgressIndicator] setDoubleValue:percent];
	[[self tracksProgressIndicator] setDoubleValue:track];
	[[self overallProgressIndicator] setDoubleValue:overall];
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
	[[self tracksProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished."]];
	[[self tracksProgressIndicator] setDoubleValue:100.0];
	[[self overallProgressIndicator] setDoubleValue:100.0];
	[[self currentProgressIndicator] setDoubleValue:100.0];
	[[self currentPercentLabel] setStringValue:@"100.00%"];
	[[self tracksPercentLabel] setStringValue:@"100.00%"];
	[[self overallPercentLabel] setStringValue:@"100.00%"];
	[self endUpdateCopyAndConvertTimer];
	[[self cancelRipButton] setTitle:@"Close"];
	[[self cancelRipButton] setEnabled:YES];
	
	NSInteger res = NSRunAlertPanel(@"Back-up Finished",
									@"Finished backing up the DVD.",
									@"Ok",
									nil,
//									@"Open Finder",
									nil);
	if(res == NSAlertAlternateReturn)
	{
		[[NSWorkspace sharedWorkspace] openFile:[_outputFileBasePath stringByDeletingLastPathComponent]];
	}
}
-(void) dvdMirrorStarted
{
	NSLog(@"Mirror Started");
	[[self currentProgressLabel] setStringValue:@"Mirror Started..."];
	[[self currentProgressIndicator] setDoubleValue:0.0];
	[[self currentPercentLabel] setStringValue:@"0.00%"];
	[[self tracksProgressLabel] setHidden:YES];
	[[self tracksProgressIndicator] setHidden:YES];
	[[self tracksPercentLabel] setHidden:YES];
	[[self overallProgressLabel] setHidden:YES];
	[[self overallProgressIndicator] setHidden:YES];
	[[self overallPercentLabel] setHidden:YES];
	[self setCurrentPage:POPMp4DVDPageRipping];
	[self startUpdateMirrorTimer];
}
-(void) dvdMirrorProgress:(float)percent
{
	[[self currentProgressIndicator] setDoubleValue:percent];
}
-(void) dvdMirrorEnded
{
	NSLog(@"Mirror Ended");
	[[self currentProgressLabel] setStringValue:[NSString stringWithFormat:@"Rip Finished"]];
	[[self currentProgressIndicator] setDoubleValue:100.0];
	[[self currentPercentLabel] setStringValue:@"100.00%"];
	[self endUpdateMirrorTimer];
	[[self cancelRipButton] setEnabled:YES];
	[[self cancelRipButton] setTitle:@"Close"];
	
	NSRunAlertPanel(@"Back-up Finished",
					@"Finished backing up the DVD.",
					@"Ok",
					nil,
					nil);
}

@end
