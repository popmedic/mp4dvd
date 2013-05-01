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
#include <dirent.h>

#import "POPDvdTracks.h"
#import "POPmp4v2dylibloader.h"

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
-(id)initWithDevicePath:(NSString*)path open:(BOOL)openDevice
{
	self = [self init];
	
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
				_devicePath = [[NSString stringWithCString:device_path encoding:NSStringEncodingConversionAllowLossy] copy];
			}
		}
		else
		{
			NSRunAlertPanel(@"DEVICE NOT FOUND",
							[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (unable to get device path from volume path).", path],
							@"Ok", nil, nil);
			return nil;
		}
	}
	else
	{
		NSRunAlertPanel(@"DEVICE NOT FOUNT",
						[NSString stringWithFormat:@"Sorry the path %@ is not a DVD device (must start with /dev/ or /Volumes/).", path],
						@"Ok", nil, nil);
		return nil;
	}
	if(openDevice == YES)
	{
		if([self openDeviceWithPath:path])
		{
			return self;
		}
		else{
			return nil;
		}
	}
	return self;
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

#pragma mark Copy

-(void)runCopyThread:(NSArray*)paths
{
	NSString* dvdPath = [paths objectAtIndex:0];
	NSString* trackTitle = [paths objectAtIndex:1];
	NSString* outPath = [[paths objectAtIndex:2] copy];
	//float durationInSecs = [[paths objectAtIndex:3] floatValue];
	long trackNum = [trackTitle integerValue];
	
	[self setIsCopying:YES];
	
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
	
	//let the delegate know we are starting the copy and convertion.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertStarted) withObject:nil waitUntilDone:NO];
	//let the delegate know we started copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	//open the menu file and decrypt the CSS
	dvd_file_t* trackMenuFile = DVDOpenFile(dvd, 0, DVD_READ_MENU_VOBS);
	//now open the track
	dvd_file_t* trackFile = DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = DVDFileSize(trackFile);
	
	unsigned char buffer[DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([[[outPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"vob"] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = DVDREADBLOCKS_BLOCK_COUNT;
	int missed_blocks = 0;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		memset(buffer, 0, sizeof(char)*DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT);
		readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < MAX_DVDREADBLOCKS_TRYS && readBlocks < 0 && [self isCopying])
			{
				tries++;
				readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
				missed_blocks++;
				if(missed_blocks > MAX_DVDREADBLOCKS_UNREAD_BLOCKS)
				{
					_error = [NSString stringWithFormat:@"Missed %i blocks in a row, unable to copy DVD.", missed_blocks];
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
			missed_blocks = 0;
		}
		else
		{
			readBlocks = DVDREADBLOCKS_SKIP_BLOCKS;
		}
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyProgress:) withObject:[NSNumber numberWithDouble:((double)offset/(double)fileSizeInBlocks)*100.0] waitUntilDone:NO];
		offset += readBlocks;
		if((offset + DVDREADBLOCKS_BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = DVDREADBLOCKS_BLOCK_COUNT;
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
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyEnded) withObject:nil waitUntilDone:NO];
	//let the delegate know we finished - hack for ease of display
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertEnded) withObject:nil waitUntilDone:NO];
}

-(BOOL)copyTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration
{
	//let the delegate know we are starting the copy and convertion. - hack for ease of display.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	
	NSArray* paths = [NSArray arrayWithObjects:[self devicePath], [trackTitle copy], [outputPath copy], [duration copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runCopyThread:) toTarget:self withObject:paths];
	
	return true;
}

#pragma mark Copy and Convert

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
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertStarted) withObject:nil waitUntilDone:NO];
	
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
	long ms, st = 0, cell = 0;
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
		st = st + ms;
		NSString* chapter_length = [NSString stringWithFormat:@"%f", (float)((ms * 0.001)+0.1)];
		if((float)(st * 0.001) >= (float)(durationInSecs-0.1))
		{
			chapter_length = [NSString stringWithFormat:@"%f", durationInSecs];
		}
		NSString* chapter_title  = [NSString stringWithFormat:@"%i", i+1];
		NSDictionary* chapter = [NSDictionary dictionaryWithObjectsAndKeys:chapter_title, @"Title", chapter_length, @"Length", nil];
		[chapters addObject:chapter];
	}
#pragma mark Copy VOB file.
	//let the delegate know we started copying.
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyStarted) withObject:nil waitUntilDone:NO];
	//open the menu file and decrypt the CSS
	dvd_file_t* trackMenuFile = DVDOpenFile(dvd, 0, DVD_READ_MENU_VOBS);
	//now open the track
	dvd_file_t* trackFile = DVDOpenFile(dvd, tt_srpt->title[trackNum-1].title_set_nr, DVD_READ_TITLE_VOBS);
	//get the file block size
	ssize_t fileSizeInBlocks = DVDFileSize(trackFile);
	
	unsigned char buffer[DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT];
	NSLog(@"Track: %@, Size: %li blocks", trackTitle, fileSizeInBlocks);
	//open the out file
	FILE* outFile = fopen([[tempPath copy] cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w+");
	//read in a block and write it out...
	ssize_t readBlocks=0;
	int offset = 0;
	long bc = DVDREADBLOCKS_BLOCK_COUNT;
	int missed_blocks = 0;
	while(offset < fileSizeInBlocks && [self isCopying])
	{
		memset(buffer, 0, sizeof(char)*DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT);
		readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
		if(readBlocks < 0)
		{
			int tries = 0;
			while (tries < MAX_DVDREADBLOCKS_TRYS && readBlocks < 0 && [self isCopying])
			{
				tries++;
				readBlocks = DVDReadBlocks(trackFile, offset, bc, buffer);
			}
			if(readBlocks < 0)
			{
				NSLog(@"Unable to read block %i", offset);
				missed_blocks++;
				if(missed_blocks > MAX_DVDREADBLOCKS_UNREAD_BLOCKS)
				{
					_error = [NSString stringWithFormat:@"Missed %i blocks in a row, unable to copy DVD.", missed_blocks];
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
			missed_blocks = 0;
		}
		else
		{
			readBlocks = DVDREADBLOCKS_SKIP_BLOCKS;
		}
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyProgress:) withObject:[NSNumber numberWithDouble:((double)offset/(double)fileSizeInBlocks)*100.0] waitUntilDone:NO];
		offset += readBlocks;
		if((offset + DVDREADBLOCKS_BLOCK_COUNT) < fileSizeInBlocks)
		{
			bc = DVDREADBLOCKS_BLOCK_COUNT;
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
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyEnded) withObject:nil waitUntilDone:NO];
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
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(ffmpegEnded:) withObject:[NSNumber numberWithInteger:0] waitUntilDone:NO];
	}
#pragma mark Add mp4 chapters
	//add the mp4 chapter marks.
	MP4FileHandle mp4File = _MP4Modify([outPath cStringUsingEncoding:NSStringEncodingConversionAllowLossy], 0);
	if(mp4File != NULL)
	{
		MP4Chapter_t* mp4Chapters = malloc(sizeof(MP4Chapter_t)*[chapters count]);
		for(int i = 0; i < [chapters count]; i++)
		{
			mp4Chapters[i].duration = [[[chapters objectAtIndex:i] objectForKey:@"Length"] doubleValue] * 1000;
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
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(copyAndConvertEnded) withObject:nil waitUntilDone:NO];
}

-(BOOL)copyAndConvertTrack:(NSString*)trackTitle To:(NSString*)outputPath Duration:(NSString*)duration
{
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [trackTitle copy], [outputPath copy], [duration copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runCopyAndConvertThread:) toTarget:self withObject:paths];
	return true;
}

#pragma mark Mirror DVD

-(void)runMirrorDVDThread:(NSArray*)paths
{
	NSError* error;
	NSString* device_path = [paths objectAtIndex:0];
	dvd_reader_t* dvd;
	NSString* dvd_path = [paths objectAtIndex:1];
	NSString* output_path = [paths objectAtIndex:2];
	NSString* video_ts_path = nil;
	NSString* mirror_to_path = nil;
	BOOL file_exists, is_dir;
	int i;
	unsigned long j;
	NSArray* video_ts_files;
	unsigned long video_ts_size;
	unsigned long src_file_size;
	NSString* src_file_path;
	NSString* dest_file_path;
	long title_nr, sub_title_nr;
	dvd_file_t* src_file;
	FILE* dest_file;
	unsigned char buffer[DVD_VIDEO_LB_LEN*DVDREADBLOCKS_BLOCK_COUNT];
	unsigned long bytes_read;
	int block_count = DVDREADBLOCKS_BLOCK_COUNT, file_block_count;
	long blocks;
	
	//tell the delegate we started
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorStarted) withObject:nil waitUntilDone:NO];
	[self setIsCopying:YES];
	//open the dvd
	dvd = DVDOpen([device_path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
	if(dvd == NULL)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"Unable to open DVD:%@\n\nDevice:\n\t%@",
						 dvd_path, device_path],
						@"Ok",
						nil,
						nil);
		return;
	}
#pragma mark Set video_ts_path
	//Set the from directory, it should be dvd_path with "/VIDEO_TS" or "/video_ts"
	NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dvd_path error:&error];
	if(files == nil)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"Unable to read Directory:%@\n\nReason:\n\t%@",
						 dvd_path, [error description]],
						@"Ok",
						nil,
						nil);
		DVDClose(dvd);
		return;
	}
	//cycle though looking for VIDEO_TS (makes case not matter)
	for(NSString* file in files)
	{
		if([file compare:@"video_ts" options:NSCaseInsensitiveSearch] == 0)
		{
			video_ts_path = [dvd_path stringByAppendingPathComponent:file];
		}
	}
	//make sure we found something
	if(video_ts_path == nil)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"Unable to find a VIDEO_TS folder in:%@", dvd_path],
						@"Ok",
						nil,
						nil);
		DVDClose(dvd);
		return;
	}
	//make sure what we found is a directory
	file_exists = [[NSFileManager defaultManager] fileExistsAtPath:video_ts_path isDirectory:&is_dir];
	if(!file_exists || !is_dir)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"VIDEO_TS folder \"%@\" does not exist or is not a folder.",video_ts_path],
						@"Ok",
						nil,
						nil);
		DVDClose(dvd);
		return;
	}

#pragma mark set destination path
	
	//We always start with a new directory, so if output_path exists, we will make output_path+"[i]"...
	i = 0;
	mirror_to_path = [output_path copy];
	while([[NSFileManager defaultManager] fileExistsAtPath:mirror_to_path isDirectory:&is_dir] && is_dir)
	{
		mirror_to_path = [output_path stringByAppendingFormat:@"[%i]", ++i];
	}
	//now tack the last component of video_ts_path (should be /VIDEO_TS) onto it...
	mirror_to_path = [mirror_to_path stringByAppendingPathComponent:[video_ts_path lastPathComponent]];
	//create the copy_to_path directory
	if([[NSFileManager defaultManager] createDirectoryAtPath:mirror_to_path
								 withIntermediateDirectories:YES
												  attributes:nil
													   error:&error] == NO)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"Unable to create directory:%@\n\nReason:\n\t%@",
						 mirror_to_path, [error description]],
						@"Ok",
						nil,
						nil);
		DVDClose(dvd);
		return;
	}
	
#pragma mark Size up folder DVD/VIDEO_TS
	video_ts_files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:video_ts_path error:&error];
	if(video_ts_files == nil)
	{
		//if this didn't work let the world know...
		if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
		NSRunAlertPanel(@"Mirror DVD Error",
						[NSString stringWithFormat:@"Unable to get contents of folder:%@\n\nReason:\n\t%@",
						 video_ts_path, [error description]],
						@"Ok",
						nil,
						nil);
		DVDClose(dvd);
		return;
	}
	//run though the contents, add up the sizes of all *.VOB, *.IFO, *.BUP files.
	video_ts_size = 0;
	for(i = 0; i < [video_ts_files count]; i++)
	{
		src_file_path = [video_ts_path stringByAppendingPathComponent:[video_ts_files objectAtIndex:i]];
		if([src_file_path compare:@"."] != 0 ||
		   [src_file_path compare:@".." ] != 0)
		{
			video_ts_size = video_ts_size + [[[NSFileManager defaultManager] attributesOfItemAtPath:src_file_path error:nil][NSFileSize] longLongValue];
		}
	}
	NSLog(@"%@ total size = %lu", video_ts_path, video_ts_size);
	
#pragma mark Copy files loop
	bytes_read = 0;
	for(i = 0; i < [video_ts_files count] && [self isCopying]; i++)
	{
		//get the file to copy...
		src_file_path = [video_ts_path stringByAppendingPathComponent:[video_ts_files objectAtIndex:i]];
		//make sure it is not . or ..
		if([src_file_path compare:@"."] != 0 ||
		   [src_file_path compare:@".." ] != 0)
		{
			src_file_size = [[[NSFileManager defaultManager] attributesOfItemAtPath:src_file_path error:nil][NSFileSize] longLongValue];
			//set the destination file.
			dest_file_path = [mirror_to_path stringByAppendingPathComponent:[video_ts_files objectAtIndex:i]];
//			file name format in VIDEO_TS:
//				VIDEO_TS.[IFO, BUP, VOB] - main menu files.
//				VTS_TT_S.[IFO, BUP, VOB] - title files.
//					where TT is the title number and S is the sub-title number.
			//get the title number, we don't have to worry about VIDEO_TS file, integerValue will make it 0.
			NSArray* parts = [(NSString*)[video_ts_files objectAtIndex:i] componentsSeparatedByString:@"_"];
			title_nr = [[parts objectAtIndex:1] integerValue];
			//now get the sub-title number
			parts = [(NSString*)[video_ts_files objectAtIndex:i] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_."]];
			if([parts count] >= 3)
			{
				sub_title_nr = [[parts objectAtIndex:2] integerValue];
			}
			else
			{
				sub_title_nr = 0;
			}
			NSLog(@"title/sub for %@: %li/%li", src_file_path, title_nr, sub_title_nr);
#pragma mark IFO file copy
			//switch on file extention, all file types are copied differently... CSS again.
			if([[src_file_path pathExtension] compare:@"IFO" options:NSCaseInsensitiveSearch] == 0)
			{
				//an IFO file, just read and write...
				src_file = DVDOpenFile(dvd, (int)title_nr, DVD_READ_INFO_FILE);
				if(src_file == NULL)
				{
					//if this didn't work let the world know...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
					NSRunAlertPanel(@"Mirror DVD Error",
									[NSString stringWithFormat:@"Unable to open file:%@",
									 src_file_path],
									@"Ok",
									nil,
									nil);
					fclose(dest_file);
					DVDClose(dvd);
					return;
				}
				//open the destination stream
				dest_file = fopen([dest_file_path cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w");
				if(dest_file == NULL)
				{
					//if this didn't work let the world know...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
					NSRunAlertPanel(@"Mirror DVD Error",
									[NSString stringWithFormat:@"Unable to open file:%@",
									 dest_file_path],
									@"Ok",
									nil,
									nil);
					DVDClose(dvd);
					return;
				}
				for(j = 0; j*DVD_VIDEO_LB_LEN < src_file_size; j++)
				{
					bytes_read += DVDReadBytes(src_file, buffer, DVD_VIDEO_LB_LEN);
					fwrite(buffer, DVD_VIDEO_LB_LEN, sizeof(unsigned char), dest_file);
					//let our delegate know where we are at...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorProgress:) withObject:[NSNumber numberWithFloat:(float)(bytes_read / video_ts_size)*100.0f] waitUntilDone:NO];
				}
				DVDCloseFile(src_file);
				fclose(dest_file);
			}
			else if([[src_file_path pathExtension] compare:@"BUP" options:NSCaseInsensitiveSearch] == 0)
			{
#pragma mark BUP file copy
				//a BUP file, just read and copy
				src_file = DVDOpenFile(dvd, (int)title_nr, DVD_READ_INFO_BACKUP_FILE);
				if(src_file == NULL)
				{
					//if this didn't work let the world know...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
					NSRunAlertPanel(@"Mirror DVD Error",
									[NSString stringWithFormat:@"Unable to open file:%@",
									 src_file_path],
									@"Ok",
									nil,
									nil);
					DVDClose(dvd);
					return;
				}
				//open the destination stream
				dest_file = fopen([dest_file_path cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w");
				if(dest_file == NULL)
				{
					//if this didn't work let the world know...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
					NSRunAlertPanel(@"Mirror DVD Error",
									[NSString stringWithFormat:@"Unable to open file:%@",
									 dest_file_path],
									@"Ok",
									nil,
									nil);
					DVDCloseFile(src_file);
					DVDClose(dvd);
					return;
				}
				for(j = 0; j*DVD_VIDEO_LB_LEN < src_file_size; j++)
				{
					bytes_read += DVDReadBytes(src_file, buffer, DVD_VIDEO_LB_LEN);
					fwrite(buffer, DVD_VIDEO_LB_LEN, sizeof(unsigned char), dest_file);
					//let our delegate know where we are at...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorProgress:) withObject:[NSNumber numberWithFloat:(float)(bytes_read / video_ts_size)*100.0] waitUntilDone:NO];
					
				}
				DVDCloseFile(src_file);
				fclose(dest_file);
			}
			else if([[src_file_path pathExtension] compare:@"VOB" options:NSCaseInsensitiveSearch] == 0)
			{
#pragma mark VOB file copy
				unsigned long start = 0;
				if(sub_title_nr == 0 || title_nr == 0  ) //menu files
				{
					src_file = DVDOpenFile(dvd, (int)title_nr, DVD_READ_MENU_VOBS);
					start = 0;
				}
				else
				{
					src_file = DVDOpenFile( dvd, (int)title_nr, DVD_READ_TITLE_VOBS );
				}
				//open the destination stream
				dest_file = fopen([dest_file_path cStringUsingEncoding:NSStringEncodingConversionAllowLossy], "w");
				if(dest_file == NULL)
				{
					//if this didn't work let the world know...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
					NSRunAlertPanel(@"Mirror DVD Error",
									[NSString stringWithFormat:@"Unable to open file:%@",
									 dest_file_path],
									@"Ok",
									nil,
									nil);
					DVDCloseFile(src_file);
					DVDClose(dvd);
					return;
				}
				if(sub_title_nr == 1 || sub_title_nr == 0 )
				{
					start = 0;
				}
				if(sub_title_nr > 1 && sub_title_nr < 9)
				{
					unsigned long single_vob_size = 0;
					int a;
					NSString* t_src_file_path;
					for(a = 1; a < sub_title_nr; a++)
					{
						t_src_file_path = [src_file_path stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"_%li.", title_nr]
																				   withString:[NSString stringWithFormat:@"_%i.", a]];
						single_vob_size += [[[NSFileManager defaultManager] attributesOfItemAtPath:src_file_path error:nil][NSFileSize] longLongValue];
					}

					start = ( single_vob_size / DVD_VIDEO_LB_LEN );
				}
				file_block_count = block_count;
				for(j = start; (j - start)*DVD_VIDEO_LB_LEN < src_file_size && [self isCopying]; j += file_block_count)
				{
					int tries = 0, skipped_blocks = 0;
					if((j - start + file_block_count) * DVD_VIDEO_LB_LEN > src_file_size )
					{
						file_block_count = (int)((src_file_size / DVD_VIDEO_LB_LEN) - (j - start));
					}

					while((blocks = DVDReadBlocks(src_file, (int)j, file_block_count, buffer)) <= 0 && tries < 3 && [self isCopying])
					{
						if(tries == 2)
						{
							j += file_block_count;
							skipped_blocks +=1;
							tries=0;
						}
						tries++;
					}
					long br = blocks * DVD_VIDEO_LB_LEN;
					bytes_read += blocks * DVD_VIDEO_LB_LEN;
					fwrite(buffer, br, sizeof(unsigned char), dest_file);
					//let our delegate know where we are at...
					if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorProgress:) withObject:[NSNumber numberWithFloat:(float)((float)bytes_read / (float)video_ts_size)*100.0] waitUntilDone:NO];
				}
				DVDCloseFile(src_file);
				fclose(dest_file);
			}
		}
	}

	DVDClose(dvd);
	//the end
	if([self delegate] != nil) [[self delegate] performSelectorOnMainThread:@selector(mirrorEnded) withObject:nil waitUntilDone:NO];
}

-(BOOL)mirrorDVD:(NSString*)outputPath
{
	NSArray* paths = [NSArray arrayWithObjects:[[self devicePath] copy], [[self path] copy], [outputPath copy], nil];
	
	[NSThread detachNewThreadSelector:@selector(runMirrorDVDThread:) toTarget:self withObject:paths];
	return true;
}

#pragma mark Terminate Thread

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

#pragma mark Property Getters/Setters

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

#pragma mark POPFfmpegDelegate Callbacks

-(void) ffmpegStarted
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegStarted) withObject:nil waitUntilDone:NO];
}
-(void) ffmpegProgress:(float)percent
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegProgress:) withObject:[NSNumber numberWithFloat:percent] waitUntilDone:NO];
}
-(void) ffmpegEnded:(NSInteger)returnCode
{
	if([self delegate] != nil)[[self delegate] performSelectorOnMainThread:@selector(ffmpegEnded:) withObject:[NSNumber numberWithInteger:returnCode] waitUntilDone:NO];
}
@end
