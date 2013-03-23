//
//  POPDvdTracks.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvdTracks.h"
#import "POPLsDvd.h"
#import "POPXMLReader.h"
#import "POPTimeConverter.h"

@implementation POPDvdTrackChapter

-(id)initWithXmlNode:(NSDictionary*)node
{
	self = [super init];
	
	_title = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"ix", @"text", nil]] copy];
	_lengthInSeconds = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"length", @"text", nil]] floatValue];
	
	return self;
}

@end

@implementation POPDvdTrackChapters
{
	NSMutableArray* _chapters;
}

-(id)initWithXmlNode:(NSDictionary*)node
{
	self = [super init];
	
	_chapters = [[NSMutableArray alloc] init];
	
	if([node isKindOfClass:[NSArray class]])
	{
		for (NSDictionary* chapter in node)
		{
			POPDvdTrackChapter* chap = [[POPDvdTrackChapter alloc] initWithXmlNode:chapter];
			[self addChapter:chap];
		}
	}
	else if([node isKindOfClass:[NSDictionary class]])
	{
		POPDvdTrackChapter* chap = [[POPDvdTrackChapter alloc] initWithXmlNode:node];
		[self addChapter:chap];
	}
	
	return self;
}

-(BOOL)addChapter:(POPDvdTrackChapter*)chapter
{
	[_chapters addObject:chapter];
	return TRUE;
}

-(POPDvdTrackChapter*)removeChapterAt:(NSUInteger)idx
{
	if([_chapters count] < idx)
	{
		POPDvdTrackChapter* rtn = [self chapterAt:idx];
		[_chapters removeObjectAtIndex:idx];
		return rtn;
	}
	return nil;
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

-(id)initWithXmlNode:(NSDictionary*)node
{
	self = [super init];
	
	_lengthInSeconds = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"length", @"text", nil]] floatValue];
	
	_title = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"ix", @"text", nil]] copy];
	_state = @"0";
	_chapters = [[POPDvdTrackChapters alloc] initWithXmlNode:[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"chapter", nil]]];
	
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
	
	POPLsDvd* lsDvd = [[POPLsDvd alloc] initWithDvdPath:path];
	if([lsDvd launch])
	{
		rtn = [[POPDvdTracks alloc] initWithXmlNode:[POPXMLReader safeDictionaryGet:[lsDvd result]
																			   path:[NSArray arrayWithObjects:@"lsdvd", nil]]];
	}
	else
	{
		NSLog(@"%@", [[lsDvd xmlParseError] description]);
	}
	
	return rtn;
}


/*NSLog(@"%@", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:node
 options:0
 error:nil]
 encoding:NSUTF8StringEncoding]);*/

-(id)initWithXmlNode:(NSDictionary*)node
{
	POPDvdTrack* trck = nil;
	float mtl = [[[NSUserDefaults standardUserDefaults] objectForKey:@"min-track-length"] floatValue];
	if(mtl <= 0.0) mtl = 30.0;
	
	self = [super init];
	
	_tracks = [[NSMutableArray alloc] init];
	_device = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"device", @"text", nil]] copy];
	_title = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"title", @"text", nil]] copy];
	_longestTrack = [[POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"longest_track", @"text", nil]] copy];
	if([_title compare:@"unknown"] == 0)
	{
		_title = [[_device lastPathComponent] copy];
	}
	id tracks = [POPXMLReader safeDictionaryGet:node path:[NSArray arrayWithObjects:@"track", nil]];
	if(tracks != @"")
	{
		if([tracks isKindOfClass:[NSArray class]])
		{
			for (NSDictionary* track in tracks)
			{
				trck = [[POPDvdTrack alloc] initWithXmlNode:track];
				if([trck lengthInSeconds] >= mtl)
				{
					if([[trck title] compare:[self longestTrack]] == 0)
					{
						[trck setState:@"1"];
					}
					[self addTrack:trck];
				}
			}
		}
		else if([tracks isKindOfClass:[NSDictionary class]])
		{
			trck = [[POPDvdTrack alloc] initWithXmlNode:tracks];
			if([trck lengthInSeconds] >= mtl)
			{
				if([[trck title] compare:[self longestTrack]] == 0)
				{
					[trck setState:@"1"];
				}
				[self addTrack:trck];
			}
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
