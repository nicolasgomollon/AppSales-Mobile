//
//  Subscription.m
//  AppSales
//
//  Created by Darren Jones on 04/01/2023.
//  Copyright © 2023 omz:software. All rights reserved.
//

#import "Subscription.h"

@implementation Subscription
@dynamic parentIdentifier;
@dynamic subscription;
@dynamic period;
@dynamic proceedsReason;
@dynamic preservedPricing;
@dynamic orderType;

- (SubscriptionType)type {
    NSString *subscriptionType = self.subscription;
    if ([subscriptionType isEqualToString:@"New"]) {
        return SubscriptionTypeNew;
    }
    return SubscriptionTypeRenewal;
}

- (void)setType:(SubscriptionType)type {
    NSAssert(NO, @"Do not set the type directly");
}

@end
