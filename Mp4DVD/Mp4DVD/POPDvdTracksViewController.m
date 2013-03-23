//
//  POPDvdTracksViewController.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvdTracksViewController.h"
#import "POPDvdTracks.h"
#import "POPTimeConverter.h"

@implementation POPDvdTracksViewController
{
	POPDvdTracks* _tracks;
	NSMutableArray* _useTracks;
}

-(id) initWithTracks:(POPDvdTracks*)tracks
{
	self = [super init];
	_tracks = tracks;
	_useTracks = [[NSMutableArray alloc] init];
	return self;
}



- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return (int)[_tracks trackCount];
}

- (id)tableView:(NSTableView*)aTableView
objectValueForTableColumn:(NSTableColumn*)aTableColumn
			row:(NSInteger)rowIndex
{
	if(rowIndex < [_tracks trackCount])
	{
		POPDvdTrack* track = [_tracks trackAt:rowIndex];
		if(track != nil)
		{
			NSUInteger colIdx = [[aTableColumn identifier] integerValue];
			if(colIdx == 1)
			{
				return [track state];
			}
			else if(colIdx == 2)
			{
				return [NSString stringWithFormat:@"%@-%@", [_tracks title], [track title]];
			}
			else if(colIdx == 3)
			{
				return [POPTimeConverter timeStringFromSecs:[track lengthInSeconds]];
			}
			else if(colIdx == 4)
			{
				return [NSString stringWithFormat:@"%li", [[track chapters] chapterCount]];
			}
		}
	}
	
	return nil;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
			  row:(NSInteger)rowIndex
{
	if(rowIndex < [_tracks trackCount])
	{
		NSUInteger colIndex = [[aTableColumn identifier] integerValue];
		if(colIndex == 1)
		{
			POPDvdTrack* track = [_tracks trackAt:rowIndex];
			BOOL currentState = [[track state] boolValue];
			if(currentState)
			{
				[[_tracks trackAt:rowIndex] setState:@"0"];
			}
			else
			{
				[[_tracks trackAt:rowIndex] setState:@"1"];
			}
		}
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	
}

@end
