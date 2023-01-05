//
//  ReportRecalculateCacheOperation.h
//  AppSales
//
//  Created by Darren Jones on 05/01/2023.
//  Copyright © 2023 omz:software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ASAccount;

@interface ReportRecalculateSalesCacheOperation : NSOperation {
    
    ASAccount *_account;
    NSPersistentStoreCoordinator *psc;
    NSManagedObjectID *accountObjectID;
}

- (instancetype)initWithAccount:(ASAccount *)account;

@end
