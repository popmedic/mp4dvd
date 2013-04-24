//
//  POPDvd2Mp4.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvd2Mp4.h"
#import "POPmp4v2dylibloader.h"

@implementation POPDvd2Mp4TrackConverter
{
	NSArray* _stages;
	POPDvd* _dvd;
}
-(id)initWithTrack:(POPDvdTrack *)track
		   dvdPath:(NSString*)dvdPath
	outputFilePath:(NSString*)outputFilePath
{
	self = [self init];
	
	_delegate = nil;
	_stages = nil;
	_track = track;
	_dvdPath = dvdPath;
	_outputFileName = [outputFilePath copy];
	_isConverting = NO;
	
	/*_tempFolderPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[_outputFileName lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]]];
	[[NSFileManager defaultManager] createDirectoryAtPath:_tempFolderPath
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];*/
	_tempFolderPath = [[outputFilePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[[[_outputFileName lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]]];
	/*[[NSFileManager defaultManager] createDirectoryAtPath:_tempFolderPath
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];*/
	/*_vobcopy = [[POPVobcopy alloc] initWithDvdPath:dvdPath
											 title:[track title]
										outputPath:_tempFolderPath];
	//_concat = [[POPConcat alloc] initWithInputFolder:_tempFolderPath];*/
	//_ffmpeg = nil;//[[POPFfmpeg alloc] initWithInputPath:[_concat outputFilePath] OutputPath:outputFilePath Duration:[track lengthInSeconds]];
	
	//[_vobcopy setDelegate:self];
	//[_concat setDelegate:self];
	//[_ffmpeg setDelegate:self];
	
	_dvd = [[POPDvd alloc] initWithDevicePath:dvdPath];
	[_dvd setDelegate:self];
	return self;
}

-(void) copyStarted
{
	NSLog(@"DVDTrackConverter: copy started");
	_stage = POPDvd2Mp4StageVobcopy;
	if(_delegate != nil)
	{
		[_delegate startStage:POPDvd2Mp4StageVobcopy];
	}
}
-(void) copyProgress:(NSNumber*)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:POPDvd2Mp4StageVobcopy progress:[percent doubleValue]];
	}
}
-(void) copyEnded
{
	NSLog(@"DVDTrackConverter: copy ended");
	if(_delegate != nil)
	{
		[_delegate endStage:POPDvd2Mp4StageVobcopy];
	}
	/*if(_isConverting)
	{
		_ffmpeg = [[POPFfmpeg alloc] initWithInputPath:_tempFilePath OutputPath:[_outputFileName copy] Duration:[_track lengthInSeconds]];
		[_ffmpeg setDelegate:self];
		[_ffmpeg launch];
	}*/
}
-(void)copyAndConvertStarted
{
	NSLog(@"Copy and convert started.");
	if(_delegate != nil)
	{
		[_delegate startConverter];
	}
}
-(void)copyAndConvertEnded
{
	NSLog(@"Copy and convert ended.");
	if(_delegate != nil)
	{
		[_delegate endConverter];
	}
}

-(void) ffmpegStarted
{
	NSLog(@"DVDTrackConverter: ffmpeg started");
	_stage = POPDvd2Mp4StageVob2Mp4;
	if(_delegate != nil)
	{
		[_delegate startStage:POPDvd2Mp4StageVob2Mp4];
	}
}
-(void) ffmpegProgress:(NSNumber*)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:POPDvd2Mp4StageVob2Mp4 progress:[percent floatValue]];
	}
}
-(void) ffmpegEnded:(NSNumber*)returnCode
{
	NSLog(@"DVDTrackConverter: ffmpeg ended");
	
	_isConverting = NO;
	if(_delegate != nil)
	{
		[_delegate endStage:POPDvd2Mp4StageVob2Mp4];
	}
	
}

-(BOOL) launch
{
	_isConverting = YES;
	/*_tempFilePath = [[[_outputFileName stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]] stringByAppendingPathExtension:@"vob"];
	[_dvd copyTrack:[_track title] To:_tempFilePath];*/
	[_dvd copyAndConvertTrack:[_track title] To:_outputFileName Duration:[NSString stringWithFormat:@"%f", [_track lengthInSeconds]]];	
	return YES;
}

-(BOOL) terminate
{
	_isConverting = NO;
	if(_stage == POPDvd2Mp4StageVobcopy)
	{
		[_dvd terminateCopyTrack];
	}
	else if(_stage == POPDvd2Mp4StageVob2Mp4)
	{
		[_dvd terminateCopyTrack];
	}
	return YES;
}
@end

@implementation POPDvd2Mp4

-(id)initWithTracks:(POPDvdTracks*)tracks
			dvdPath:(NSString*)dvdPath
	 outputFileBasePath:(NSString*)outputFileBasePath
{
	POPDvdTrack* track = nil;
	NSString* outputFilePath;
	
	self = [super init];
	
	_delegate = nil;
	_currentConverterIndex = 0;
	_tracks = tracks;
	_dvdPath = dvdPath;
	_outputFileBasePath = outputFileBasePath;
	_outputFileBaseName = [outputFileBasePath lastPathComponent];
	
	_trackConverters = [[NSMutableArray alloc] init];
	NSArray* convertTracks = [_tracks convertTracks];
	if([convertTracks count] > 1)
	{
		for (int i = 0; i < [convertTracks count]; i++)
		{
			track = [convertTracks objectAtIndex:i];
			outputFilePath = [_outputFileBasePath stringByAppendingFormat:@"[%i].mp4", i+1];
			[self addTrackConverterWithTrack:track outputFilePath:outputFilePath];
		}
	}
	else if([convertTracks count] == 1)
	{
		track = [convertTracks objectAtIndex:0];
		outputFilePath = [_outputFileBasePath stringByAppendingPathExtension:@"mp4"];
		[self addTrackConverterWithTrack:track outputFilePath:outputFilePath];
	}
	
	return self;
}

-(void)addTrackConverterWithTrack:(POPDvdTrack*)track outputFilePath:(NSString*)outputFilePath
{
	POPDvd2Mp4TrackConverter* tc = [[POPDvd2Mp4TrackConverter alloc] initWithTrack:track
																		   dvdPath:_dvdPath
																	outputFilePath:outputFilePath];
	[tc setDelegate:self];
	[_trackConverters addObject:tc];
}

-(BOOL) launch
{
	POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
	if(_delegate != nil)
	{
		[_delegate dvdRipStarted];
	}
	_isConverting = YES;
	[tc launch];
	return YES;
}

-(BOOL) terminate
{
	POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
	_isConverting = NO;
	[tc terminate];
	return YES;
}

-(void)startConverter
{
	if(_delegate != nil)
	{
		[_delegate converterStarted:_currentConverterIndex+1 Of:[_trackConverters count]];
	}
}
-(void)startStage:(POPDvd2Mp4Stage)stage
{
	if(_delegate != nil)
	{
		[_delegate stageStarted:stage+1 Of:POPDvd2Mp4NumberOfStages];
	}
}
-(void)stageProgress:(POPDvd2Mp4Stage)stage progress:(float)percent
{
	if(_delegate != nil)
	{
		[_delegate stageProgress:stage progress:percent];
	}
}
-(void)endStage:(POPDvd2Mp4Stage)stage
{
	if(_delegate != nil)
	{
		[_delegate stageEnded:stage+1 Of:POPDvd2Mp4NumberOfStages];
	}
}
-(void)endConverter
{
	if(_isConverting)
	{
		++_currentConverterIndex;
		if(_delegate != nil)
		{
			[_delegate converterEnded:_currentConverterIndex Of:[_trackConverters count]];
		}
		
		if(_currentConverterIndex < [_trackConverters count])
		{
			POPDvd2Mp4TrackConverter* tc = [_trackConverters objectAtIndex:_currentConverterIndex];
			[tc launch];
		}
		else
		{
			_isConverting = NO;
			if(_delegate != nil)
			{
				[_delegate dvdRipEnded];
			}
		}
	}
	else
	{
		if(_delegate != nil)
		{
			[_delegate converterEnded:_currentConverterIndex Of:[_trackConverters count]];
		}
		if(_delegate != nil)
		{
			[_delegate dvdRipEnded];
		}
	}
}

@end
