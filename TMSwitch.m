/*
 TMSwitch.m
 Created 2010-02-19 by Sven-S. Porst <ssp-web@earthlingsoft.net>
 
 The MIT License
 
 Copyright (c) 2010-2011 Sven-S. Porst
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
*/

#import <Foundation/Foundation.h>
#import <sys/mount.h>

NSString * const TMSwitchBundleID = @"net.earthlingsoft.TMSwitch";
NSString * const TMSwitchVolumeUUIDsKey = @"volumeUUIDs";

NSString * const TMDefaultsFilePath = @"/Library/Preferences/com.apple.TimeMachine";
NSString * const TMDefaultsAliasDataKey = @"BackupAlias";
NSString * const TMDefaultsUUIDKey = @"DestinationVolumeUUID";
NSString * const TMDefaultsAutoBackupKey = @"AutoBackup";
NSString * const TMUtilPath = @"/usr/bin/tmutil";



NSString * UUIDForVolumeURL ( NSURL * volumeURL ) {
	NSString * UUID = nil;
	
	const char * volumePath = [[volumeURL path] cStringUsingEncoding: NSUTF8StringEncoding];
	struct statfs stats;
	if ( statfs(volumePath, &stats) != -1 ) {
		const char * devicePath = stats.f_mntfromname;

		DASessionRef session = DASessionCreate(NULL);
		if ( session != NULL ) {
			CFMakeCollectable(session);
			DADiskRef disk = DADiskCreateFromBSDName(NULL, session, devicePath);
			CFMakeCollectable(disk);
			if ( disk != NULL ) {
				NSDictionary * diskProperties = (NSDictionary*) DADiskCopyDescription(disk);
				CFMakeCollectable(diskProperties);
				CFUUIDRef theUUID = (CFUUIDRef) [diskProperties objectForKey: (NSString*) kDADiskDescriptionVolumeUUIDKey];
				if ( theUUID != NULL ) {
					UUID = (NSString*) CFUUIDCreateString(NULL, theUUID);
				}
			}
		}
	}
	
	return UUID;
}



BOOL isQualifiedVolumeUUID ( NSString * UUID ) {
	BOOL result = NO;
	
	NSUserDefaults * UD = [NSUserDefaults standardUserDefaults];
	NSDictionary * defaults = [UD persistentDomainForName: TMSwitchBundleID];
	NSArray * volumeUUIDs = [defaults objectForKey: TMSwitchVolumeUUIDsKey];
	
	if ( [volumeUUIDs containsObject: UUID] ) {
		result = YES;
	}
	
	return result;
}



BOOL switchVolume () {
	BOOL switchedVolume = NO;
	
	NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
	NSString * currentVolumeUUID = [[userDefaults persistentDomainForName:TMDefaultsFilePath] objectForKey: TMDefaultsUUIDKey];
	
	NSArray * volumeURLs = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:nil options:NSVolumeEnumerationSkipHiddenVolumes];

	for ( NSURL * volumeURL in volumeURLs ) {
		NSString * volumeUUID = UUIDForVolumeURL( volumeURL );
		if ( isQualifiedVolumeUUID(volumeUUID) ) {
			
			if ( ! [volumeUUID isEqualToString: currentVolumeUUID ] ) {
				NSArray * tmutilOptions = [NSArray arrayWithObjects:@"setdestination", [volumeURL path], nil];
				NSTask * task = [NSTask launchedTaskWithLaunchPath:TMUtilPath arguments:tmutilOptions];
				[task waitUntilExit];
				
				if ([task terminationStatus] == 0) {
					NSLog(@"Switched Time Machine volume to %@.", [volumeURL path]);
					switchedVolume = YES;
				}
				else {
					NSLog(@"Failed to switch Time Machine volume to %@.", [volumeURL path]);
					
				}
			}
			else {
				NSLog(@"Time Machine volume does not need to be changed.");
			}
			
			break;
		}
	}
	[userDefaults synchronize];
	
	return switchedVolume;
}



BOOL switchTimeMachine ( BOOL newStatus ) {
	BOOL switchedTimeMachine = NO;
	NSArray * tmutilOptions = [NSArray arrayWithObject:(newStatus ? @"enable" : @"disable")];
	NSTask * task = [NSTask launchedTaskWithLaunchPath:TMUtilPath arguments:tmutilOptions];
	[task waitUntilExit];
	
	if ([task terminationStatus] == 0) {
		NSLog(@"Turned Time Machine %@.", (newStatus ? @"on" : @"off"));
		switchedTimeMachine = YES;
	}
	else {
		NSLog(@"Failed to turn Time Machine %@.", (newStatus ? @"on" : @"off"));
		
	}
	
	return switchedTimeMachine;
}



BOOL toggleTimeMachine () {
	BOOL success = NO;
	
	NSDate * now = [NSDate date];
	NSDictionary * locale =  [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
	NSString * timeZone = [now descriptionWithCalendarFormat:@"%z" timeZone:nil locale:locale];
	NSString * date = [now descriptionWithCalendarFormat:@"%Y-%m-%d" timeZone:nil locale:locale];
	
	NSDate * turnOnTime = [NSDate dateWithString: [NSString stringWithFormat:@"%@ 08:00:00 %@", date, timeZone]];
	NSDate * turnOffTime = [NSDate dateWithString: [NSString stringWithFormat:@"%@ 22:30:00 %@", date, timeZone]];
	
	BOOL desiredTimeMachineStatus = ( [turnOnTime compare:now] == NSOrderedAscending
									 && [turnOffTime compare:now] == NSOrderedDescending );
	
	NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
	NSDictionary * TMDefaults = [userDefaults persistentDomainForName: TMDefaultsFilePath];
	const BOOL actualTimeMachineStatus = [[TMDefaults objectForKey: TMDefaultsAutoBackupKey] boolValue];
	
	if ( actualTimeMachineStatus != desiredTimeMachineStatus ) {
		success = switchTimeMachine(desiredTimeMachineStatus);
	}

	return success;
}



int main (int argc, const char * argv[]) {
	if ( argc == 1 ) {
		// no parameters, just switch the volume and change Time Machine’s status
		BOOL needsToBackup = switchVolume() || toggleTimeMachine();
		
		if ( needsToBackup ) {
			// defaults were changed: run Time Machine
			[NSTask launchedTaskWithLaunchPath:TMUtilPath arguments:[NSArray arrayWithObject:@"startbackup"]];
		}
	}
	else if ( argc == 2 ) {
		NSString * arg2 = [NSString stringWithUTF8String:argv[1]];
		if ( [arg2 isEqualToString: @"help"] || [arg2 isEqualToString: @"-v"] ) {
			NSLog(@"TMSwitch - set Time Machine to use the first known volume it can find.");
			NSLog(@"TMSwitch [add|remove] /Volumes/BackupVolume - edit known volumes.");
			NSLog(@"TMSwitch list - list  UUIDs of known volumes.");
			NSLog(@"Source code at: http://github.com/ssp/TMSwitch");
		}
		else if ( [arg2 isEqualToString: @"list"] ) {
			NSArray * myUUIDs = [[[NSUserDefaults standardUserDefaults] persistentDomainForName: TMSwitchBundleID] objectForKey: TMSwitchVolumeUUIDsKey];
			if ( myUUIDs && [myUUIDs count] > 0 ) {
				NSLog(@"TMSwitch’s known volume UUIDs:");
				for ( NSString * theUUID in myUUIDs ) {
					NSLog(@"%@\n", theUUID);
				}
			}
			else {
				NSLog(@"No volume IDs are set up for use with TMSwitch.\nUse TMSwitch add to add some or TMSwitch help for more information.");
			}
		}
	}
	else if ( argc == 3 ) {
		// 3 parameters: hope the middle one is a verb and the last one a path to a volume, then try to add that
		NSString * arg2 = [NSString stringWithUTF8String:argv[1]];
		NSString * arg3 = [NSString stringWithUTF8String:argv[2]];
		NSURL * URL = [NSURL fileURLWithPath: arg3];
		NSString * UUID = UUIDForVolumeURL( URL );
		if ( UUID != nil ) {
			NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
			NSDictionary * originalDefaults = [userDefaults persistentDomainForName: TMSwitchBundleID];
			NSMutableDictionary * defaults;
			if ( originalDefaults == nil ) {
				defaults = [NSMutableDictionary dictionaryWithCapacity:1];
			}
			else {
				defaults = [originalDefaults mutableCopy];
			}
			
			NSMutableArray * UUIDs = [[defaults objectForKey:TMSwitchVolumeUUIDsKey] mutableCopy];
			if ( UUIDs == nil ) {
				UUIDs = [NSMutableArray arrayWithCapacity:1];
			}
			
			if ( [arg2 isEqualToString: @"add"] && ![UUIDs containsObject: UUID] ) {
				[UUIDs addObject: UUID];
			}
			else if ( [arg2 isEqualToString: @"remove"] && [UUIDs containsObject: UUID] ) {
				[UUIDs removeObject: UUID];
			}
			
			[defaults setValue:UUIDs forKey:TMSwitchVolumeUUIDsKey];
			[userDefaults setPersistentDomain:defaults forName:TMSwitchBundleID];
			[userDefaults synchronize];
		}
	}
	
    return 0;
}
