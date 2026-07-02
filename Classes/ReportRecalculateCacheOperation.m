//
//  ReportRecalculateCacheOperation.m
//  AppSales
//
//  Created by Darren Jones on 05/01/2023.
//  Copyright © 2023 omz:software. All rights reserved.
//

#import "ReportRecalculateCacheOperation.h"
#import "ASAccount.h"
#import "Report.h"

@implementation ReportRecalculateSalesCacheOperation

- (instancetype)initWithAccount:(ASAccount *)account {
    self = [super init];
    if (self) {
        _account = account;
        accountObjectID = [[account objectID] copy];
        psc = [[account managedObjectContext] persistentStoreCoordinator];
    }
    return self;
}

- (void)main {
    @autoreleasepool {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_account.downloadStatus = NSLocalizedString(@"Starting re-import of reports", nil);
            self->_account.downloadProgress = 0.0;
        });
        
        NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [moc setPersistentStoreCoordinator:psc];
        [moc setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        
        ASAccount *account = (ASAccount *)[moc objectWithID:accountObjectID];
        
        // Fetch all the daily reports
        NSSet *allDailyReports = account.dailyReports;
        NSArray *sortDescriptors = @[[[NSSortDescriptor alloc] initWithKey:@"startDate" ascending:YES]];
        NSMutableArray *sortedDailyReports = [NSMutableArray new];
        [sortedDailyReports addObjectsFromArray:[allDailyReports allObjects]];
        [sortedDailyReports sortUsingDescriptors:sortDescriptors];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_account.downloadStatus = [NSString stringWithFormat:NSLocalizedString(@"Processing report (0/%lu)...", nil), (unsigned long)[sortedDailyReports count]];
            self->_account.downloadProgress = 0.0;
        });
        
        NSInteger numberOfReportsImported = 0;
        // Loop through all reports
        for (Report *report in sortedDailyReports) {
            NSString *reportCSV = [report valueForKeyPath:@"originalReport.content"];
            NSString *fileName = [report valueForKeyPath:@"originalReport.filename"];
            
            // Create a new report
            Report *newReport = [Report insertNewReportWithCSV:reportCSV inAccount:account with:moc];
            if (newReport) {
                // Copy the old csv and filename over to the new report
                NSManagedObject *originalReport = [NSEntityDescription insertNewObjectForEntityForName:@"ReportCSV" inManagedObjectContext:moc];
                [originalReport setValue:reportCSV forKey:@"content"];
                [originalReport setValue:newReport forKey:@"report"];
                [originalReport setValue:fileName forKey:@"filename"];
                
                [newReport generateCache];
            }
            
            // Delete the old report now we have a new one
            [moc deleteObject:report];
            
            __block NSError *saveError = nil;
            [psc performBlockAndWait:^{
                [moc save:&saveError];
                if (saveError) {
                    NSLog(@"Could not save context: %@", saveError);
                }
            }];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                float progress = (float)numberOfReportsImported / (float)[sortedDailyReports count];
                self->_account.downloadStatus = [NSString stringWithFormat:NSLocalizedString(@"Processing report (%li/%lu)...", nil), (long)numberOfReportsImported, (unsigned long)[sortedDailyReports count]];
                self->_account.downloadProgress = progress;
            });
            numberOfReportsImported++;
        }
    }
}

@end
