//
//  POPDvdCopy.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/26/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "POPDvd.h"

@protocol POPDvdCopyDelegate <NSObject>
-(void) dvdMirrorStarted;
-(void) dvdMirrorProgress:(float)percent;
-(void) dvdMirrorEnded;
@end

@interface POPDvdCopy : NSObject <POPDvdDelegate>

@property (assign) NSString* path;
@property (assign) id<POPDvdCopyDelegate> delegate;
@property (assign) BOOL isCopying;

-(id)initWithDevicePath:(NSString*)path;
-(void)launchWithOutputPath:(NSString*)outputPath;
-(void)terminate;

@end
