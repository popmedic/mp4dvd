//
//  POPlibdvddylibloader.m
//  Mp4DVD
//
//  Created by Kevin Scardina on 4/3/13.
//  Copyright (c) 2013 Popmedic Labs. All rights reserved.
//

#import "POPlibdvddylibloader.h"

#include <dlfcn.h>

@implementation POPlibdvddylibloader
+(void)loadLibDvd:(NSString*)path
{
	void *lib_read_handle = 0, *lib_css_handle = 0;
	lib_read_handle = dlopen("libdvdread.4.dylib", RTLD_LOCAL|RTLD_LAZY);
	if(!lib_read_handle)
	{
		lib_read_handle = dlopen([[[NSBundle mainBundle] pathForResource:@"libdvdread.4.dylib" ofType:@"dylib"] cStringUsingEncoding:NSUTF8StringEncoding], RTLD_LOCAL|RTLD_LAZY);
		
	}
	if(!lib_read_handle)
	{
		lib_read_handle = dlopen([path cStringUsingEncoding:NSUTF8StringEncoding], RTLD_LOCAL|RTLD_LAZY);
		
	}
	if(!lib_read_handle)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:[NSString stringWithFormat:@"Unable to load %@", path]
									 userInfo:nil];
	}
	lib_css_handle = dlopen("libdvdcss.2.dylib", RTLD_LOCAL|RTLD_LAZY);
	if(!lib_css_handle)
	{
		lib_css_handle = dlopen([[[NSBundle mainBundle] pathForResource:@"libdvdcss.2.dylib" ofType:@"dylib"] cStringUsingEncoding:NSUTF8StringEncoding], RTLD_LOCAL|RTLD_LAZY);
	}
	
	_DVDOpen          = dlsym(lib_read_handle, "DVDOpen");
	_DVDClose         = dlsym(lib_read_handle, "DVDClose");
	_DVDOpenFile      = dlsym(lib_read_handle, "DVDOpenFile");
	_DVDCloseFile     = dlsym(lib_read_handle, "DVDOpen");
	_DVDReadBlocks    = dlsym(lib_read_handle, "DVDReadBlocks");
	_DVDFileSeek      = dlsym(lib_read_handle, "DVDFileSeek");
	_DVDReadBytes     = dlsym(lib_read_handle, "DVDReadBytes");
	_DVDFileSize      = dlsym(lib_read_handle, "DVDFileSize");
	_DVDDiscID        = dlsym(lib_read_handle, "DVDDiscID");
	_DVDUDFVolumeInfo = dlsym(lib_read_handle, "DVDUDFVolumeInfo");
	_DVDFileSeekForce = dlsym(lib_read_handle, "DVDFileSeekForce");
	_DVDISOVolumeInfo = dlsym(lib_read_handle, "DVDISOVolumeInfo");
	_DVDUDFCacheLevel = dlsym(lib_read_handle, "DVDUDFCacheLevel");
	_ifoOpen          = dlsym(lib_read_handle, "ifoOpen");
	_ifoClose         = dlsym(lib_read_handle, "ifoClose");
	
	if(!_DVDOpen)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDOpen"
									 userInfo:nil];
	}
	if(!_DVDClose)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDClose"
									 userInfo:nil];
	}
	if(!_DVDOpenFile)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDOpenFile"
									 userInfo:nil];
	}
	if(!_DVDCloseFile)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDCloseFile"
									 userInfo:nil];
	}
	if(!_DVDReadBlocks)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDReadBlocks"
									 userInfo:nil];
	}
	if(!_DVDFileSeek)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDFileSeek"
									 userInfo:nil];
	}
	if(!_DVDReadBytes)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDReadBytes"
									 userInfo:nil];
	}
	if(!_DVDFileSize)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDFileSize"
									 userInfo:nil];
	}
	if(!_DVDDiscID)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDDiscID"
									 userInfo:nil];
	}
	if(!_DVDUDFVolumeInfo)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDVolumeInfo"
									 userInfo:nil];
	}
	if(!_DVDFileSeekForce)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDFileSeakForce"
									 userInfo:nil];
	}
	if(!_DVDISOVolumeInfo)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDISOVolumeInfo"
									 userInfo:nil];
	}
	if(!_DVDUDFCacheLevel)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function DVDUDFCacheLevel"
									 userInfo:nil];
	}
	if(!_ifoOpen)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function ifoOpen"
									 userInfo:nil];
	}
	if(!_ifoClose)
	{
		@throw [NSException exceptionWithName:@"FileNotFoundException"
									   reason:@"Unable to load function ifoOpen"
									 userInfo:nil];
	}
}
@end
