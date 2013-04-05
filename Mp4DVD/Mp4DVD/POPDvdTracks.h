//
//  POPDvdTracks.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface POPDvdTrackChapter : NSObject

@property (readonly, assign) NSString* title;
@property (readonly, assign) float lengthInSeconds;

-(id)initWithDictionary:(NSDictionary*)chapter;

@end

@interface POPDvdTrackChapters : NSObject

-(id)initWithArray:(NSArray*)chapters;
-(BOOL)addChapter:(POPDvdTrackChapter*)chapter;
-(POPDvdTrackChapter*)chapterAt:(NSUInteger)idx;
-(NSInteger)chapterCount;

@end

@interface POPDvdTrack : NSObject

@property (readonly, assign) NSString* title;
@property (readonly, assign) float lengthInSeconds;
@property (readonly, assign) POPDvdTrackChapters* chapters;
@property (readwrite, assign) NSString* state;

-(id)initWithDictionary:(NSDictionary*)track;

@end

@interface POPDvdTracks : NSObject

+(id)dvdTracksFromDvdPath:(NSString*)path;

@property (readonly, assign) NSString* device;
@property (readwrite, assign) NSString* title;
@property (readonly, assign) NSString* longestTrack;

-(id)initWithDictionary:(NSDictionary*)contents;
-(BOOL)addTrack:(POPDvdTrack*)track;
-(POPDvdTrack*)removeTrackAt:(NSUInteger)idx;
-(POPDvdTrack*)trackAt:(NSUInteger)idx;
-(NSInteger)trackCount;
-(NSArray*)convertTracks;
-(NSInteger)convertTrackCount;

@end
