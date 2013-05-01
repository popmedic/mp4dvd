//
//  POPDvdTracks.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvdTracks.h"
#import "POPDvd.h"
#import "POPTimeConverter.h"

@implementation POPDvdTrackChapter

-(id)initWithDictionary:(NSDictionary*)chapter
{
	self = [super init];
	
	_title = [chapter objectForKey:@"Title"];
	_lengthInSeconds = [[chapter objectForKey:@"Length"] floatValue];
	
	return self;
}

@end

@implementation POPDvdTrackChapters
{
	NSMutableArray* _chapters;
}

-(id)initWithArray:(NSArray*)chapters
{
	self = [super init];
	
	_chapters = [[NSMutableArray alloc] init];
	
	for(int i = 0; i < [chapters count]; i++)
	{
		[self addChapter:[[POPDvdTrackChapter alloc] initWithDictionary:[chapters objectAtIndex:i]]];
	}
	
	return self;
}

-(BOOL)addChapter:(POPDvdTrackChapter*)chapter
{
	[_chapters addObject:chapter];
	return TRUE;
}

-(POPDvdTrackChapter*)chapterAt:(NSUInteger)idx
{
	return [_chapters objectAtIndex:idx];
}

-(NSInteger)chapterCount
{
	return [_chapters count];
}

@end

@implementation POPDvdTrack

-(id)initWithDictionary:(NSDictionary*)track
{
	self = [super init];
	
	_title = [[track objectForKey:@"Title"] copy];
	_lengthInSeconds = [[track objectForKey:@"Length"] floatValue];
	_state = @"0";
	_chapters = [[POPDvdTrackChapters alloc] initWithArray:[track objectForKey:@"Chapters"]];
	
	return self;
}
@end

@implementation POPDvdTracks
{
	NSMutableArray* _tracks;
}

+(id)dvdTracksFromDvdPath:(NSString*)path
{
	POPDvdTracks* rtn = nil;
	
	POPDvd* dvd = [[POPDvd alloc] initWithDevicePath:path open:YES];
	rtn = [[POPDvdTracks alloc] initWithDictionary:[dvd contents]];
	dvd = nil;
	
	return rtn;
}

-(id)initWithDictionary:(NSDictionary*)contents
{
	float mtl = [[[NSUserDefaults standardUserDefaults] objectForKey:@"min-track-length"] floatValue];
	if(mtl <= 0.0) mtl = 30.0;
	
	self = [super init];
	
	_tracks = [[NSMutableArray alloc] init];
	_device = [contents objectForKey:@"Title"];
	_title = [contents objectForKey:@"Title"];;
	_longestTrack = [contents objectForKey:@"LongestTrack"];;
	if([_title compare:@"unknown"] == 0)
	{
		_title = [_device lastPathComponent];
	}
	NSArray* tracks = [contents objectForKey:@"Tracks"];
	for (NSDictionary* track in tracks)
	{
		POPDvdTrack* trck = [[POPDvdTrack alloc] initWithDictionary:track];
		if([trck lengthInSeconds] >= mtl)
		{
			if([[trck title] compare:[self longestTrack]] == 0)
			{
				[trck setState:@"1"];
			}
			[self addTrack:trck];
		}
	}
	return self;
}

-(BOOL)addTrack:(POPDvdTrack*)track
{
	[_tracks addObject:track];
	return TRUE;
}

-(POPDvdTrack*)removeTrackAt:(NSUInteger)idx
{
	if([_tracks count] < idx)
	{
		POPDvdTrack* rtn = [self trackAt:idx];
		[_tracks removeObjectAtIndex:idx];
		return rtn;
	}
	return nil;
}

-(POPDvdTrack*)trackAt:(NSUInteger)idx
{
	return [_tracks objectAtIndex:idx];
}

-(NSInteger)trackCount
{
	return [_tracks count];
}

-(NSArray*)convertTracks
{
	NSArray* rtn = [NSArray array];
	for(POPDvdTrack* track in _tracks)
	{
		if([[track state] boolValue])
		{
			rtn = [rtn arrayByAddingObject:track];
		}
	}
	return rtn;
}

-(NSInteger)convertTrackCount
{
	NSInteger rtn = 0;
	for(POPDvdTrack* track in _tracks)
	{
		if([[track state] boolValue])
		{
			++rtn;
		}
	}
	return rtn;
}
@end
