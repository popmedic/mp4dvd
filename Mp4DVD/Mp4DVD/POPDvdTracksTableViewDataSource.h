//
//  POPDvdTracksViewController.h
//  Mp4DVD
//
//  Created by Kevin Scardina on 3/21/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "POPDvdTracks.h"

@interface POPDvdTracksTableViewDataSource : NSObject
-(id) initWithTracks:(POPDvdTracks*)tracks;
@end
