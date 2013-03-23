//
//  POPDropDVDImageView.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/20/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol POPDropDVDImageViewDelegate
-(void)dvdDragEnded:(NSString*)path;
@end

@interface POPDropDVDImageView : NSImageView
@property (assign) BOOL isHighlighted;
@property (readwrite,retain) id<POPDropDVDImageViewDelegate> delegate;
@end
