//
//  ReviewDownloadManager.h
//  AppSales
//
//  Created by Ole Zorn on 27.07.11.
//  Copyright 2011 omz:software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ReviewsParser.h"

#define ReviewDownloadManagerDidUpdateProgressNotification	@"ReviewDownloadManagerDidUpdateProgressNotification"

@class Product, ReviewDownload;

@protocol ReviewDownloadDelegate <NSObject>

- (void)reviewDownloadDidFinish:(ReviewDownload *)download;

@end


@interface ReviewDownloadManager : NSObject <ReviewDownloadDelegate> {

	NSMutableSet *activeDownloads;
	NSMutableArray *downloadQueue;
	
	NSInteger totalDownloadsCount;
	NSInteger completedDownloadsCount;
}

+ (id)sharedManager;
- (void)downloadReviewsForProducts:(NSArray *)products;
- (void)cancelAllDownloads;
- (BOOL)isDownloading;
- (float)downloadProgress;

@end


@interface ReviewDownload : NSObject {
	id<ReviewDownloadDelegate> __weak delegate;
	NSPersistentStoreCoordinator *psc;
	Product *_product;
	NSManagedObjectID *productObjectID;
	
	NSString *country;
	NSURLConnection *downloadConnection;
	NSMutableData *data;
	NSInteger page;
	
	UIBackgroundTaskIdentifier backgroundTaskID;
	
	BOOL canceled;
}

@property (nonatomic, weak) id<ReviewDownloadDelegate> delegate;
@property (nonatomic, strong) NSURLConnection *downloadConnection;

- (id)initWithProduct:(Product *)app countryCode:(NSString *)countryCode;
- (void)start;
- (void)cancel;

@end