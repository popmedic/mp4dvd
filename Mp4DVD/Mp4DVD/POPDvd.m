//
//  POPDvd.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPDvd.h"

#include <mp4v2/mp4v2.h>
#include <dvdread/dvd_reader.h>
#include <dvdread/ifo_types.h>
#include <dvdread/ifo_read.h>
#include <dvdread/nav_read.h>
#include <dvdread/nav_print.h>
#include <sys/mount.h>

typedef struct dvd_input_s *dvd_input_t;
struct dvd_reader_s {
	/* Basic information. */
	int isImageFile;
	
	/* Hack for keeping track of the css status.
	 * 0: no css, 1: perhaps (need init of keys), 2: have done init */
	int css_state;
	int css_title; /* Last title that we have called dvdinpute_title for. */
	
	/* Information required for an image file. */
	dvd_input_t dev;
	
	/* Information required for a directory path drive. */
	char *path_root;
	
	/* Filesystem cache */
	int udfcache_level; /* 0 - turned off, 1 - on */
	void *udfcache;
};

#import "POPDvdTracks.h"
#import "POPmp4v2dylibloader.h"

#define MAX_UNREAD_BLOCKS 10

long dvdtime2msec(dvd_time_t *dt)
{
	double frames_per_s[4] = {-1.0, 25.00, -1.0, 29.97};
	double fps = frames_per_s[(dt->frame_u & 0xc0) >> 6];
	long   ms;
	ms  = (((dt->hour &   0xf0) >> 3) * 5 + (dt->hour   & 0x0f)) * 3600000;
	ms += (((dt->minute & 0xf0) >> 3) * 5 + (dt->minute & 0x0f)) * 60000;
	ms += (((dt->second & 0xf0) >> 3) * 5 + (dt->second & 0x0f)) * 1000;
	
	if(fps > 0)
		ms += ((dt->frame_u & 0x30) >> 3) * 5 + (dt->frame_u & 0x0f) * 1000.0 / fps;
	
	return ms;
}

bool device_path_with_volume_path(char *device_path, const char *volume_path, int max_device_path)
{
	struct statfs *mntbufp;
	int num_of_mnts = 0;
	int i;
	
	/* get our mount infos */
	num_of_mnts = getmntinfo(&mntbufp, MNT_WAIT);
	if(num_of_mnts == 0) /* no mounts returned, something is drastically wrong. */
	{
		fprintf(stderr, "No mounts???\n");
		return false;
	}
	/* go though the mounts and see which one matches volume_path */
	for(i = 0; i < num_of_mnts; i++)
	{
		/* fprintf(stdout, "[INFO Mount: %i (%s on %s)]\n", i, mntbufp[i].f_mntfromname, mntbufp[i].f_mntonname); */
		if(strcmp(volume_path, mntbufp[i].f_mntonname) == 0)
		{
			strncpy(device_path, mntbufp[i].f_mntfromname, max_device_path); /* copy the device_path */
			return true; /* found our guy, so, get out of here! */
		}
	}
	return false; /* couldn't find our guy sorry :-( */
}

@implementation POPDvd
{
	NSString* _path;
	NSString* _devicePath;
	BOOL _isCopying;
	id<POPDvdDelegate> _delegate;
	POPFfmpeg* _ffmpeg;
	volatile NSArray* _tracks;
}
-(id)init
{
	self = [super init];
	_contents = nil;
	_delegate = nil;
	_ffmpeg = nil;
	[self setIsCopying:NO];
	_error = @"none";
	@synchronized(self)
	{
		_path=@"";
	}
	return self;
}
-(id)initWithDevicePath:(NSString*)path
{
	self = [self init];
	if([self openDeviceWithPath:path])
	{
		return self;
	}
	else{
		return nil;
	}
}

-(BOOL)openDeviceWithPath:(NSString*)path
{
	dvd_reader_t *dvd;
	ifo_handle_t *ifo_zero, **ifo;
	vtsi_mat_t *vtsi_mat;
	vmgi_mat_t *vmgi_mat;
	pgcit_t *vts_pgcit;
	pgc_t *pgc;
	int i, j, vts_ttn, title_set_nr;
	long max_length=0;
	NSString* max_track = @"0";
	_title = [path lastPathComponent];
	if(_contents != nil) _contents = nil;
	
	@synchronized(self)
	{
		_path = [path copy];
	}
	//make sure we have a good devicePath
	if([[_path substringWithRange:NSMakeRange(0, 5)] compare:@"/dev/"] == 0)
	{
		@synchronized(self)
		{
			_devicePath = [path copy];
		}
	}
	else if([[_path substringWithRange:NSMakeRange(0, [@"/Volumes/" length])] compare:@"/Volumes/"] == 0)
	{
		char device_path[1024];
		if(device_path_with_volume_path(device_path, [path cStringUsingEncoding:NSStringEncodingConversionAllowLossy],1024))
		{
			@synchronized(self)
			{
				_devicePath = [NSString stringWithCString:device_path encoding:NSStringEncodingConversionAllowLossy ];
			}
		}
		else
		{
			NSRunAlertPanel(@"DEVICE NOT FOUND",
							[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (unable to get device path from volume path).", path],
							@"Ok", nil, nil);
		}
	}
	else
	{
		NSRunAlertPanel(@"DEVICE NOT FOUNT",
						[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (must start with /dev/ or /Volumes/).", path],
						@"Ok", nil, nil);
	}
	dvd = DVDOpen([[self devicePath] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	if(!dvd)
	{
		NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open DVD: %@" ,path], @"Ok",nil, nil);
		return false;
	}
	
	ifo_zero = ifoOpen(dvd, 0);
	if(!ifo_zero)
	{
		NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open main IFO\nDVD Path: %@", path], @"Ok",nil, nil);
		return false;
	}
	
	ifo = (ifo_handle_t **)malloc((ifo_zero->vts_atrt->nr_of_vtss + 1) * sizeof(ifo_handle_t *));
	for (i=1; i <= ifo_zero->vts_atrt->nr_of_vtss; i++)
	{
		ifo[i] = ifoOpen(dvd, i);
		if ( !ifo[i] ) {
			NSRunAlertPanel(@"libdvdread ERROR", [NSString stringWithFormat:@"unable to open IFO: %i\nDVD Path: %@", i, path], @"Ok",nil, nil);
			return false;
		}
	}
	@synchronized(self)
	{
		_numberOfTracks = ifo_zero->tt_srpt->nr_of_srpts;
	}
	
	NSMutableArray* tracks = [NSMutableArray array];
	vmgi_mat = ifo_zero->vmgi_mat;
	//go though the tracks.
	for (j=0; j < _numberOfTracks; j++)
	{
		//general track info
		if (ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vtsi_mat)
		{
			
			vtsi_mat = ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vtsi_mat;
			vts_pgcit = ifo[ifo_zero->tt_srpt->title[j].title_set_nr]->vts_pgcit;
			vts_ttn = ifo_zero->tt_srpt->title[j].vts_ttn;
			vmgi_mat = ifo_zero->vmgi_mat;
			title_set_nr = ifo_zero->tt_srpt->title[j].title_set_nr;
			pgc = vts_pgcit->pgci_srp[ifo[title_set_nr]->vts_ptt_srpt->title[vts_ttn - 1].ptt[0].pgcn - 1].pgc;
			
			if (dvdtime2msec(&pgc->playback_time) > max_length)
			{
				max_length = dvdtime2msec(&pgc->playback_time);
				max_track = [NSString stringWithFormat:@"%i", j+1];
			}
			
			NSString* track_length = [NSString stringWithFormat:@"%f", dvdtime2msec(&pgc->playback_time)/1000.0 ];
			NSString* track_title = [NSString stringWithFormat:@"%i", j+1];
			NSMutableArray* chapters = [NSMutableArray array];
			
			//go though the chapters
			long ms, cell = 0;
			for (i=0; i<pgc->nr_of_programs; i++)
			{
				ms=0;
				int next = pgc->program_map[i+1];
				if (i == pgc->nr_of_programs - 1) next = pgc->nr_of_cells + 1;
					
				while (cell < next - 1)
				{
					ms = ms + dvdtime2msec(&pgc->cell_playback[cell].playback_time);
					cell++;
				}
				NSString* chapter_title  = [NSString stringWithFormat:@"%i", i+1];
				NSString* chapter_length = [NSString stringWithFormat:@"%f", ms * 0.001];
				NSDictionary* chapter = [NSDictionary dictionaryWithObjectsAndKeys:chapter_title, @"Title", chapter_length, @"Length", nil];
				[chapters addObject:chapter];
			}
			NSDictionary* track = [NSDictionary dictionaryWithObjectsAndKeys:track_title, @"Title", track_length, @"Length", chapters, @"Chapters", nil];
			[tracks addObject:track];
		}
	}
	
	//clean up
	for (i=1; i <= ifo_zero->vts_atrt->nr_of_vtss; i++)
	{
		ifoClose(ifo[i]);
	}
	ifoClose(ifo_zero);
	DVDClose(dvd);
	
	//set the property contents.
	@synchronized(self)
	{
		_tracks = tracks;
		_contents = [NSDictionary dictionaryWithObjectsAndKeys:_title, @"Title", max_track, @"LongestTrack", tracks, @"Tracks", nil];
	}
	return true;
}

-(void) runCopyAndConvertThread:(NSArray*)paths
{
	NSString* dvdPath = [paths objectAtIndex:0];
	NSString* trackTitle = [paths objectAtIndex:1];
	NSString* outPath = [[paths objectAtIndex:2] copy];
	float durationInSecs = [[paths objectAtIndex:3] floatValue];
	NSString* tempPath = [[[outPath stringByDeletingPathExtension] stringByAppendingFormat:@"%i",(int)[NSDate timeIntervalSinceReferenceDate]] stringByAppendingPathExtension:@"vob"];
	long trackNum = [trackTitle integerValue];
	NSMutableArray* chapters = [NSMutableArray array];
	[self setIsCopying:YES];
	//let the delegate know we are starting the copy and convertion.
	if([self delegate] != nil) [[self delegate] copyAndConvertStarted];
	
	//open the dvd
	dvd_reader_t* dvd = DVDOpen([dvdPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	
	//open the dvd image and vts info files
	ifo_handle_t* vmg_file = ifoOpen(dvd, 0);
	tt_srpt_t* tt_srpt = vmg_file->tt_srpt;
	ifo_handle_t* vts_file = ifoOpen(dvd, tt_srpt->title[trackNum-1].title_set_nr);
	
	//see if we can use passthough
	//-- in the future there will be a way to select which channel you want to encode,
	//-- but for now, I just use the first audiostream.  If this stream is 2 channel, then
	//-- we can use -vsync passthough which speeds it up and lines the audio and video up.
	int audio_attr_cnt = vts_file->vtsi_mat->nr_of_vts_audio_streams;
	audio_attr_t* audio_attrs = vts_file->vtsi_mat->vts_audio_attr;
	bool use_passthough = false;
	if(audio_attr_cnt > 0)
	{
		audio_attr_t* audio_attr = &audio_attrs[0];
		int t_channels = audio_attr->channels+1;
		if(t_channels == 2)
		{
			use_passthough = true;
		}
	}
	
#pragma mark Create chapters array.
	//grab our program chain and create chapters array.
	int ttn = tt_srpt->title[trackNum-1].vts_ttn;
	vts_ptt_srpt_t* vts_ptt_srpt = vts_file->vts_ptt_srpt;
	int pgc_id = vts_ptt_srpt->title[ttn - 1].ptt[0].pgcn;
	pgc_t* pgc = vts_file->vts_pgcit->pgci_srp[pgc_id - 1].pgc;
	//go though the chapters
	long ms, cell = 0;
	for (int i = 0; i < pgc->nr_of_programs; i++)
	{
		ms=0;
		int next = pgc->program_map[i+1];
		if (i == pgc->nr_of_programs - 1) next = pgc->nr_of_cells + 1;
		
		while (cell < next - 1)
		{
			ms = ms + dvdtime2msec(&pgc->cell_playback[cell].playback_time);
			cell++;
		}
		NSString* chapter_title  = [NSString stringWithFormat:@"%i", i+1];
		NSString* chapter_length = [NSString stringWithFormat:@"%f", ms * 0.001];
		NSDictionary* chapter = [NSDictionary dictionaryWithObjectsAndKeys:chapter_title, @"Title", chapter_length, @"Length", nil];
		[chapters addObject:chapter];
	}
#pragma mark Copy VOB file.
	//let the delegate know we started copying.
	if([self delegate] != nil) [[self delegate] copyStarted];
	//open the menu file and decrypt the CSS
	dvd_file_t* trackMenuFile = DVDOpenFile(dvd, 0, DVD_READ_MENU_VOBS);
	//now open the track
	dvd_file_t* trackFile = DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = DVDFileSize(trackFile);
	
	unsigned char buffer[DVD_VIDEO_LB_LEN*BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([[tempPath copy] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = BLOCK_COUNT;
	int missed_blocks = 0;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < 10 && readBlocks < 0)
			{
				tries++;
				readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
				missed_blocks++;
				if(missed_blocks > MAX_UNREAD_BLOCKS)
				{
					_error = [NSString stringWithFormat:@"Missed %i blocks, unable to copy DVD.", missed_blocks];
					[self setIsCopying:NO];
				}
				else
				{
					readBlocks = 0;
				}
			}
			else
			{
				NSLog(@"Read of block %i took %i tries.", offset, tries);
			}
		}
		else if(readBlocks == 0)
		{
			NSLog(@"No data read at block %i", offset);
		}
		
		if(readBlocks > 0)
		{
			fwrite(buffer, DVD_VIDEO_LB_LEN, readBlocks, outFile);
		}
		if([self delegate] != nil) [[self delegate] copyProgress:((double)offset/(double)fileSizeInBlocks)*100.0];
		offset += readBlocks;
		if((offset + BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = BLOCK_COUNT;
		}
		else
		{
			bc = fileSizeInBlocks - (long)offset;
		}
	}
	
	//clean up the DVD read.
	fclose(outFile);
	ifoClose(vmg_file);
	ifoClose(vts_file);
	DVDCloseFile(trackFile);
	DVDCloseFile(trackMenuFile);
	DVDClose(dvd);
	//let the delegate know we finsihed copying.
	if([self delegate] != nil) [[self delegate] copyEnded];
#pragma mark Convert to mp4.
	//convert to an mp4.
	if([self isCopying])
	{
		_ffmpeg = [[POPFfmpeg alloc] initWithInputPath:tempPath OutputPath:outPath Duration:durationInSecs Passthough:use_passthough];
		[_ffmpeg setDelegate:self];
		[_ffmpeg launch];
		[_ffmpeg waitUntilExit];
		_ffmpeg = nil;
	}
	else
	{
		[[self delegate] ffmpegEnded:0];
	}
#pragma mark Add mp4 chapters
	//add the mp4 chapter marks.
	MP4FileHandle mp4File = _MP4Modify([outPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy], 0);
	if(mp4File != NULL)
	{
		MP4Chapter_t* mp4Chapters = malloc(sizeof(MP4Chapter_t)*[chapters count]);
		for(int i = 0; i < [chapters count]; i++)
		{
			mp4Chapters[i].duration = [[[chapters objectAtIndex:i] objectForKey:@"Length"] doubleValue]*1000;
			strcpy(mp4Chapters[i].title, [[[chapters objectAtIndex:i] objectForKey:@"Title"] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
		}
		if(_MP4SetChapters(mp4File, mp4Chapters, (unsigned int)[chapters count], MP4ChapterTypeAny) != MP4ChapterTypeAny)
		{
			NSLog(@"Chapters were not able to be set");
		}
		_MP4Close(mp4File, 0);
		free(mp4Chapters);
	}
	
	//clean up the temp file.
	if([[NSFileManager defaultManager] fileExistsAtPath:tempPath])
	{
		NSError* error;
		if(![[NSFileManager defaultManager] removeItemAtPath:tempPath error:&error])
		{
			NSRunAlertPanel(@"Remove Temporary Folder ERROR", [NSString stringWithFormat:@"Unable to remove the temporary folder. Error: %@", [error description]], @"Ok", nil, nil);
		}
		else
		{
			NSLog(@"removed %@", tempPath);
		}
	}
	
	[self setIsCopying:NO];
	
	//let the delegate know we finished
	if([self delegate] != nil) [[self delegate] copyAndConvertEnded];
}

-(BOOL)copyAndConvertTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration
{
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [trackTitle copy], [outputPath copy], [duration copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runCopyAndConvertThread:) toTarget:self withObject:paths];
	//[self runCopyThread:paths];
	return true;
}

-(void)terminateCopyTrack
{
	if([self isCopying])
	{
		[self setIsCopying:NO];
		if(_ffmpeg != nil)
		{
			[_ffmpeg terminate];
		}
	}
}
-(NSString*)path
{
	NSString* rtn;
	@synchronized(self)
	{
		rtn = [_path copy];
	}
	return rtn;
}
-(NSString*)devicePath
{
	NSString* rtn;
	@synchronized(self)
	{
		rtn = [_devicePath copy];
	}
	return rtn;
}
-(BOOL)isCopying
{
	BOOL rtn;
	@synchronized(self)
	{
		rtn = _isCopying;
	}
	return rtn;
}
-(void)setIsCopying:(BOOL)isCopying
{
	@synchronized(self)
	{
		_isCopying = isCopying;
	}
}
-(id<POPDvdDelegate>)delegate
{
	return _delegate;
}
-(void)setDelegate:(id<POPDvdDelegate>)delegate
{
	@synchronized(self)
	{
		_delegate = delegate;
	}
}

-(void) ffmpegStarted
{
	if([self delegate] != nil)[[self delegate] ffmpegStarted];
}
-(void) ffmpegProgress:(float)percent
{
	if([self delegate] != nil)[[self delegate] ffmpegProgress:percent];
}
-(void) ffmpegEnded:(NSInteger)returnCode
{
	if([self delegate] != nil)[[self delegate] ffmpegEnded:returnCode];
}
@end
