//
//  POPDropDVDImageView.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/20/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDropDVDImageView.h"

@implementation POPDropDVDImageView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setIsHighlighted:NO];
		[self setDelegate:nil];
    }
    
    return self;
}

- (void)awakeFromNib
{
    NSLog(@"[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	if ([self isHighlighted]) {
        [NSBezierPath setDefaultLineWidth:6.0];
        [[NSColor keyboardFocusIndicatorColor] set];
        [NSBezierPath strokeRect:dirtyRect];
    }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		NSArray *paths = [pboard propertyListForType:NSFilenamesPboardType];
		if([paths count] > 0)
		{
			NSString* path = [paths objectAtIndex:0];
			BOOL is_dir;
			if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&is_dir] && is_dir)
			{
				if([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/VIDEO_TS", path] isDirectory:&is_dir] && is_dir)
				{
					[self setIsHighlighted:YES];
					[self display];
					return NSDragOperationEvery;
				}
			}
		}
	}
	[self setIsHighlighted:NO];
	[self display];
	return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	[self setIsHighlighted:NO];
	[self display];
}


- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
	if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		NSArray *paths = [pboard propertyListForType:NSFilenamesPboardType];
		if([paths count] > 0)
		{
			NSString* path = [paths objectAtIndex:0];
			BOOL is_dir;
			if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&is_dir] && is_dir)
			{
				if([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/VIDEO_TS", path] isDirectory:&is_dir] && is_dir)
				{
					[self setIsHighlighted:NO];
					[self display];
					return YES;
				}
			}
		}
	}
	[self setIsHighlighted:NO];
	[self display];
	return NO;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSLog(@"[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
	
    NSPasteboard *pboard = [sender draggingPasteboard];
	
    if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		
        NSArray *paths = [pboard propertyListForType:NSFilenamesPboardType];
        if([paths count] > 0)
		{
			NSString* path = [paths objectAtIndex:0];
			if([self delegate] != nil)
			{
				[[self delegate] dvdDragEnded:path];
			}
			NSLog(@"Open DVD %@", path);
			return YES;
		}
	}
	return NO;
}

@end
