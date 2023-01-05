//
//  Subscription.h
//  AppSales
//
//  Created by Darren Jones on 04/01/2023.
//  Copyright © 2023 omz:software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Transaction;

typedef NS_ENUM(NSUInteger, SubscriptionType) {
    SubscriptionTypeNew,
    SubscriptionTypeRenewal
};

@interface Subscription : NSManagedObject {
@private
}
@property (nonatomic, strong) NSString *parentIdentifier;   // Links to the main product SKU
@property (nonatomic, strong) NSString *subscription;       // "New" or "Renewal"
@property (nonatomic, strong) NSString *period;             // "1 Year", "1 Month" etc..
@property (nonatomic, strong) NSString *proceedsReason;     // "Rate After One Year" etc..
@property (nonatomic, assign) BOOL preservedPricing;        // "Yes" or empty
@property (nonatomic, strong) NSString *orderType;          // "Pay Up Front Intro Offer"...

@property (nonatomic) SubscriptionType type;                // A calculated enum value. Not stored in Core Data

@end
