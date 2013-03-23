//
//  POPVobcopy.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol POPVobcopyDelegate <NSObject>
-(void) vobcopyStarted;
-(void) vobcopyProgress:(float)percent;
-(void) vobcopyEnded:(NSInteger)returnCode;
@end

@interface POPVobcopy : NSObject

+(BOOL)checkIfVobcopyBinary:(NSString*)path;

@property (readwrite, retain) id<POPVobcopyDelegate> delegate;
@property (readonly, assign) BOOL isCopying;
@property (readwrite, retain, getter=vobcopyPath, setter=setVobcopyPath:) NSString* vobcopyPath;

-(id)initWithDvdPath:(NSString*)dvdPath title:(NSString*)title outputPath:(NSString*)outputPath;

-(BOOL)launch;
-(BOOL)terminate;

@end