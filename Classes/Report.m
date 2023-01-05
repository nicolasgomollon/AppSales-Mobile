//
//  Report.m
//  AppSales
//
//  Created by Ole Zorn on 02.07.11.
//  Copyright (c) 2011 omz:software. All rights reserved.
//

#import "Report.h"
#import "DailyReport.h"
#import "WeeklyReport.h"
#import "ASAccount.h"
#import "Product.h"
#import "Transaction.h"
#import "CurrencyManager.h"
#import "Subscription.h"

#define kReportColumnDeveloperProceeds		@"royalty price"			// old report format
#define kReportColumnDeveloperProceeds2		@"developer proceeds"
#define kReportColumnCurrencyOfProceeds		@"royalty currency"			// old report format
#define kReportColumnCurrencyOfProceeds2	@"currency of proceeds"
#define kReportColumnTitle					@"title / episode / season"	// old report format
#define kReportColumnTitle2					@"title"
#define kReportColumnSKU					@"vendor identifier"		// old report format
#define kReportColumnSKU2					@"sku"

#define kReportColumnProductTypeIdentifier	@"product type identifier"
#define kReportColumnUnits					@"units"
#define kReportColumnBeginDate				@"begin date"
#define kReportColumnEndDate				@"end date"
#define kReportColumnCountryCode			@"country code"
#define kReportColumnAppleIdentifier		@"apple identifier"
#define kReportColumnParentIdentifier		@"parent identifier"
#define kReportColumnCustomerPrice			@"customer price"
#define kReportColumnPromoCode				@"promo code"
#define kReportColumnVersion				@"version"

// Subscriptions
#define kReportColumnSubscription           @"subscription"             // "New" or "Renewal"
#define kReportColumnParentIdentifier       @"parent identifier"        // Links to the main product
#define kReportColumnPeriod                 @"period"                   // "1 Year", "1 Month" etc..
#define kReportColumnProceedsReason         @"proceeds reason"          // "Rate After One Year" etc..
#define kReportColumnPreservedPricing       @"preserved pricing"        // "Yes"
#define kReportColumnOrderType              @"order type"               // "Pay Up Front Intro Offer"...

@interface ReportCache : NSManagedObject

@property (nonatomic, strong) NSDictionary *content;
@property (nonatomic, strong) Report *report;

@end

@implementation ReportCache

@dynamic content, report;

@end



@implementation Report

@dynamic startDate, transactions, cache;

+ (NSDictionary *)infoForReportCSV:(NSString *)csv {
	NSMutableArray *rows = [[csv componentsSeparatedByString:@"\n"] mutableCopy];
	if ([rows count] < 3)  {
		return nil;
	}
	
	NSString *headerLine = [rows[0] lowercaseString];
	NSArray *columnHeaders = [headerLine componentsSeparatedByString:@"\t"];
	if (![self validateColumnHeaders:columnHeaders]) {
		return nil;
	}
	
	[rows removeObjectAtIndex:0];
	NSString *row = rows[0];
	NSArray *rowFields = [row componentsSeparatedByString:@"\t"];
	if ([rowFields count] > [columnHeaders count]) {
		return nil;
	}
	NSMutableDictionary *rowDictionary = [NSMutableDictionary dictionaryWithObjects:rowFields forKeys:[columnHeaders subarrayWithRange:NSMakeRange(0, [rowFields count])]];
	NSString *beginDateString = rowDictionary[kReportColumnBeginDate];
	NSString *endDateString = rowDictionary[kReportColumnEndDate];
	if (!beginDateString || !endDateString) {
		return nil;
	}
	NSDate *beginDate = [self dateFromReportDateString:beginDateString];
	NSDate *endDate = [self dateFromReportDateString:endDateString];
	if (!beginDate || !endDate) {
		return nil;
	}
	BOOL isWeeklyReport = ![beginDate isEqual:endDate];
	return @{kReportInfoClass: (isWeeklyReport ? kReportInfoClassWeekly : kReportInfoClassDaily),
			 kReportInfoDate: beginDate};
}

+ (Report *)insertNewReportWithCSV:(NSString *)csv inAccount:(ASAccount *)account {
    NSManagedObjectContext *moc = account.managedObjectContext;
    return [self insertNewReportWithCSV:csv inAccount:account with:moc];
}

+ (Report *)insertNewReportWithCSV:(NSString *)csv inAccount:(ASAccount *)account with:(NSManagedObjectContext *)moc {
	NSSet *allProducts = account.products;
	
	NSMutableDictionary *productsBySKU = [NSMutableDictionary dictionary];
	for (Product *product in allProducts) {
		NSString *SKU = product.SKU;
		if (SKU) [productsBySKU setObject:product forKey:SKU];
	}
	
	NSMutableArray *rows = [[csv componentsSeparatedByString:@"\n"] mutableCopy];
	if ([rows count] < 3)  {
		return nil;
	}
	
	NSString *headerLine = [rows[0] lowercaseString];
	NSArray *columnHeaders = [headerLine componentsSeparatedByString:@"\t"];
	if (![self validateColumnHeaders:columnHeaders]) {
		return nil;
	}
	
	[rows removeObjectAtIndex:0];
	Report *report = nil;
	for (__strong NSString *row in rows) {
		row = [row stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSArray *rowFields = [row componentsSeparatedByString:@"\t"];
		if ([rowFields count] > [columnHeaders count]) {
			continue;
		}
		NSMutableDictionary *rowDictionary = [NSMutableDictionary dictionaryWithObjects:rowFields forKeys:[columnHeaders subarrayWithRange:NSMakeRange(0, [rowFields count])]];
		NSString *beginDateString = rowDictionary[kReportColumnBeginDate];
		NSString *endDateString = rowDictionary[kReportColumnEndDate];
		if (!beginDateString || !endDateString) continue;
		NSDate *beginDate = [self dateFromReportDateString:beginDateString];
		NSDate *endDate = [self dateFromReportDateString:endDateString];
		if (!report && (!beginDate || !endDate)) {
			//Date couldn't be parsed
			return nil;
		} else {
			[rowDictionary setObject:beginDate forKey:kReportColumnBeginDate];
			[rowDictionary setObject:endDate forKey:kReportColumnEndDate];
		}
		BOOL isWeeklyReport = ![beginDate isEqual:endDate];
		NSString *productName = rowDictionary[kReportColumnTitle];
		if (!productName) productName = rowDictionary[kReportColumnTitle2];
		productName = [productName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		Transaction *transaction = [NSEntityDescription insertNewObjectForEntityForName:@"Transaction" inManagedObjectContext:moc];
		transaction.units = @([rowDictionary[kReportColumnUnits] integerValue]);
		transaction.type = rowDictionary[kReportColumnProductTypeIdentifier];
		transaction.promoType = rowDictionary[kReportColumnPromoCode];
			
		NSString *developerProceedsColumn = rowDictionary[kReportColumnDeveloperProceeds];
		if (!developerProceedsColumn) developerProceedsColumn = rowDictionary[kReportColumnDeveloperProceeds2];
		NSNumber *revenue = @([developerProceedsColumn floatValue]);
		transaction.revenue = revenue;
		
		NSString *currencyOfProceedsColumn = rowDictionary[kReportColumnCurrencyOfProceeds];
		if (!currencyOfProceedsColumn) currencyOfProceedsColumn = rowDictionary[kReportColumnCurrencyOfProceeds2];
		[transaction setValue:currencyOfProceedsColumn forKey:@"currency"];
		
		[transaction setValue:rowDictionary[kReportColumnCountryCode] forKey:@"countryCode"];
		NSString *productSKU = rowDictionary[kReportColumnSKU];
		if (!productSKU) productSKU = rowDictionary[kReportColumnSKU2];
		
		if ([productSKU hasSuffix:@" "]) { // Bug in October 26th, 2015 reports, where SKU has a trailing space.
			// First delete 'productSKU plus space' duplicate and clean up the mess.
			Product *product = productsBySKU[productSKU];
			if (product) {
				[moc deleteObject:product];
			}
			// Now fix the SKU so it does not happen again.
			int len = (int)productSKU.length;
			productSKU = [productSKU substringToIndex:len-1];
		}
		productSKU = [productSKU stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		Product *product = productsBySKU[productSKU];
		if (!product) {
			product = [NSEntityDescription insertNewObjectForEntityForName:@"Product" inManagedObjectContext:moc];
			product.parentSKU = [rowDictionary[kReportColumnParentIdentifier] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			product.account = account;
			product.productID = rowDictionary[kReportColumnAppleIdentifier];
			product.SKU = productSKU;
			product.lastModified = beginDate;
			product.name = productName;
			[productsBySKU setObject:product forKey:productSKU];
		}
		if (![product.name isEqualToString:productName]) {
			if ([beginDate timeIntervalSinceDate:product.lastModified] > 0) {
				// Only update name if the current report is newer than the one the product was created with.
				product.name = productName;
			}
		}
		[transaction setValue:product forKey:@"product"];
        
        if (rowDictionary[kReportColumnParentIdentifier] && [rowDictionary[kReportColumnParentIdentifier] length] > 2 &&
            rowDictionary[kReportColumnSubscription] && [rowDictionary[kReportColumnSubscription] length] > 2) {
            
            Subscription *subscription = [NSEntityDescription insertNewObjectForEntityForName:@"Subscription" inManagedObjectContext:moc];
            subscription.parentIdentifier = rowDictionary[kReportColumnParentIdentifier];
            subscription.subscription = rowDictionary[kReportColumnSubscription];
            subscription.period = rowDictionary[kReportColumnPeriod];
            subscription.proceedsReason = rowDictionary[kReportColumnProceedsReason];
            subscription.preservedPricing = [rowDictionary[kReportColumnPreservedPricing] isEqualToString:@"Yes"];
            subscription.orderType = rowDictionary[kReportColumnOrderType];
            
            [transaction setValue:subscription forKey:@"subscription"];
        }
		
		static NSDictionary *platformsByTransactionType = nil;
		if (!platformsByTransactionType) {
			platformsByTransactionType = @{@"1": kProductPlatformiPhone,
										   @"3": kProductPlatformiPhone,
										   @"7": kProductPlatformiPhone,
										   @"1F": kProductPlatformUniversal,
										   @"3F": kProductPlatformUniversal,
										   @"7F": kProductPlatformUniversal,
										   @"1T": kProductPlatformiPad,
										   @"3T": kProductPlatformiPad,
										   @"7T": kProductPlatformiPad,
										   @"F1": kProductPlatformMac,
										   @"F3": kProductPlatformMac,
										   @"F7": kProductPlatformMac,
										   @"IA1": kProductPlatformInApp,
										   @"IA1-M": kProductPlatformMacInApp,
										   @"IA9": kProductPlatformInApp,
										   @"IA9-M": kProductPlatformMacInApp,
										   @"1-B": kProductPlatformAppBundle,
										   @"F1-B": kProductPlatformMacAppBundle,
										   @"IAY": kProductPlatformRenewableSubscription,
										   @"IAY-M": kProductPlatformMacRenewableSubscription,
                                           @"1E": kProductPlatformiPhone,
                                           @"1EP": kProductPlatformiPad,
                                           @"1EU": kProductPlatformUniversal,
                                           @"FI1": kProductPlatformMacInApp
            };
		}
		
		NSString *platform = platformsByTransactionType[rowDictionary[kReportColumnProductTypeIdentifier]];
		if (platform) {
			product.platform = platform;
		}
		
		if (!report) {
			if (isWeeklyReport) {
				report = [NSEntityDescription insertNewObjectForEntityForName:@"WeeklyReport" inManagedObjectContext:moc];
				[(WeeklyReport *)report setEndDate:endDate];
				[(WeeklyReport *)report setAccount:account];
			} else {
				report = [NSEntityDescription insertNewObjectForEntityForName:@"DailyReport" inManagedObjectContext:moc];
				[(DailyReport *)report setAccount:account];
			}
			report.startDate = beginDate;
		}
		[[report mutableSetValueForKey:@"transactions"] addObject:transaction];
	}
	return report;
}

+ (BOOL)validateColumnHeaders:(NSArray *)columnHeaders {
	static NSSet *requiredColumnsSet1 = nil;
	static NSSet *requiredColumnsSet2 = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		requiredColumnsSet1 = [[NSSet alloc] initWithObjects:
							   kReportColumnTitle,
							   kReportColumnProductTypeIdentifier,
							   kReportColumnUnits,
							   kReportColumnDeveloperProceeds,
							   kReportColumnBeginDate,
							   kReportColumnEndDate,
							   kReportColumnCountryCode,
							   kReportColumnCurrencyOfProceeds,
							   kReportColumnAppleIdentifier,
							   kReportColumnCustomerPrice,
							   kReportColumnSKU,
							   nil];
		requiredColumnsSet2 = [[NSSet alloc] initWithObjects:
							   kReportColumnTitle2,
							   kReportColumnProductTypeIdentifier,
							   kReportColumnUnits,
							   kReportColumnDeveloperProceeds2,
							   kReportColumnBeginDate,
							   kReportColumnEndDate,
							   kReportColumnCountryCode,
							   kReportColumnCurrencyOfProceeds2,
							   kReportColumnAppleIdentifier,
							   kReportColumnParentIdentifier,
							   kReportColumnCustomerPrice,
							   kReportColumnSKU2,
							   nil];
	});
	
	NSSet *columnHeadersSet = [NSSet setWithArray:columnHeaders];
	if ([requiredColumnsSet1 isSubsetOfSet:columnHeadersSet] || [requiredColumnsSet2 isSubsetOfSet:columnHeadersSet]) {
		return YES;
	}
	return NO;
}

- (void)generateCache {
	NSMutableDictionary *tmpSummary = [NSMutableDictionary dictionary];
	NSMutableDictionary *revenueByCurrency = [NSMutableDictionary dictionary];
	[tmpSummary setObject:revenueByCurrency forKey:kReportSummaryRevenue];
	NSMutableDictionary *transactionsByType = [NSMutableDictionary dictionary];
	[tmpSummary setObject:transactionsByType forKey:kReportSummaryTransactions];
	
	for (Transaction *transaction in self.transactions) {
		NSString *currency = transaction.currency;
		NSString *productIdentifier = transaction.product.productID;
		float transactionRevenue = [transaction.revenue floatValue];
		NSInteger transactionUnits = [transaction.units integerValue];
		NSString *transactionType = transaction.type;
		if (currency) {
			float revenue = [revenueByCurrency[productIdentifier][currency] floatValue];
			revenue += (transactionRevenue * transactionUnits);
			NSMutableDictionary *revenuesForProduct = revenueByCurrency[productIdentifier];
			if (!revenuesForProduct) {
				revenuesForProduct = [NSMutableDictionary dictionary];
				[revenueByCurrency setObject:revenuesForProduct forKey:productIdentifier];
			}
			[revenuesForProduct setObject:@(revenue) forKey:currency];
		}
		if (transactionType) {
			NSString *promoType = transaction.promoType;
			// Some old reports have "FREE" as the promo code identifier for updates, in newer reports, the field is empty.
			if (promoType && ![promoType isEqualToString:@"FREE"]) {
				if (promoType && ![promoType isEqualToString:@"FREE"] && ![promoType isEqualToString:@" "]) {
					transactionType = [NSString stringWithFormat:@"%@.%@", transactionType, promoType];
				}
			}
			NSInteger count = [transactionsByType[productIdentifier][transactionType] integerValue];
			count += transactionUnits;
			NSMutableDictionary *transactionsForProduct = transactionsByType[productIdentifier];
			if (!transactionsForProduct) {
				transactionsForProduct = [NSMutableDictionary dictionary];
				[transactionsByType setObject:transactionsForProduct forKey:productIdentifier];
			}
			[transactionsForProduct setObject:@(count) forKey:transactionType];
		}
	}
	self.cache = [NSEntityDescription insertNewObjectForEntityForName:@"ReportCache" inManagedObjectContext:self.managedObjectContext];
	self.cache.content = [NSDictionary dictionaryWithDictionary:tmpSummary];
}

- (float)totalRevenueInBaseCurrency {
	float total = 0.0;
	NSDictionary *revenueByProduct = self.cache.content[kReportSummaryRevenue];
	for (NSString *productID in [revenueByProduct allKeys]) {
		NSDictionary *revenueByCurrency = revenueByProduct[productID];
		for (NSString *currency in [revenueByCurrency allKeys]) {
			float revenue = [revenueByCurrency[currency] floatValue];
			float revenueInBaseCurrency = [[CurrencyManager sharedManager] convertValue:revenue fromCurrency:currency];
			total += revenueInBaseCurrency;
		}
	}
	return total;
}

- (float)totalRevenueInBaseCurrencyForProductWithID:(NSString *)productID {
	return [self totalRevenueInBaseCurrencyForProductWithID:productID inCountry:nil];
}

- (float)totalRevenueInBaseCurrencyForProductWithID:(NSString *)productID inCountry:(NSString *)country {
	if (!country) {
		if (!productID) {
			return [self totalRevenueInBaseCurrency];
		}
		float total = 0.0;
		NSDictionary *revenueByProduct = self.cache.content[kReportSummaryRevenue];
		NSDictionary *revenueByCurrency = revenueByProduct[productID];
		for (NSString *currency in revenueByCurrency) {
			float revenue = [revenueByCurrency[currency] floatValue];
			float revenueInBaseCurrency = [[CurrencyManager sharedManager] convertValue:revenue fromCurrency:currency];
			total += revenueInBaseCurrency;
		}
		return total;
	} else {
		float total = 0.0;
		for (Transaction *transaction in self.transactions) {
			if (!productID || [transaction.product.productID isEqualToString:productID]) {
				if (!country || [transaction.countryCode isEqualToString:country]) {
					float revenue = [transaction.revenue floatValue];
					NSString *currency = transaction.currency;
					int units = [transaction.units intValue];
					float revenueInBaseCurrency = [[CurrencyManager sharedManager] convertValue:(revenue * units) fromCurrency:currency];
					total += revenueInBaseCurrency;
				}
			}
		}
		return total;
	}
}

- (NSInteger)totalNumberOfPaidDownloads {
	return [self totalNumberOfPaidDownloadsForProductWithID:nil];
}

- (NSDictionary *)totalNumberOfPaidDownloadsByCountryAndProduct {
	NSSet *paidTransactionTypes = [[self class] combinedPaidTransactionTypes];
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	for (Transaction *transaction in self.transactions) {
		NSString *type = transaction.type;
		NSString *promoType = transaction.promoType;
		if(promoType != nil) {
			promoType = [promoType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if([promoType isEqualToString:@""])promoType = nil;
		}
		NSString *combinedType = (promoType != nil) ? [NSString stringWithFormat:@"%@.%@", type, promoType] : type;
		if (![paidTransactionTypes containsObject:combinedType]) {
			continue;
		}
		NSString *transactionCountry = transaction.countryCode;
		NSString *transactionProductID = transaction.product.productID;
		NSMutableDictionary *paidDownloadsByProduct = result[transactionCountry];
		if (!paidDownloadsByProduct) {
			paidDownloadsByProduct = [NSMutableDictionary dictionary];
			[result setObject:paidDownloadsByProduct forKey:transactionCountry];
		}
		NSInteger oldNumberOfPaidDownloads = [paidDownloadsByProduct[transactionProductID] integerValue];
		NSInteger newNumberOfPaidDownloads = oldNumberOfPaidDownloads + [transaction.units integerValue];
		[paidDownloadsByProduct setObject:@(newNumberOfPaidDownloads) forKey:transactionProductID];
	}
	return result;
}

- (NSDictionary *)totalNumberOfPaidNonRefundDownloadsByCountryAndProduct {
	NSSet *paidTransactionTypes = [[self class] combinedPaidTransactionTypes];
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	for (Transaction *transaction in self.transactions) {
		if (transaction.units.integerValue < 0) {
			continue;
		}
		NSString *type = transaction.type;
		NSString *promoType = transaction.promoType;
		if(promoType != nil) {
			promoType = [promoType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if([promoType isEqualToString:@""])promoType = nil;
		}
		NSString *combinedType = (promoType != nil) ? [NSString stringWithFormat:@"%@.%@", type, promoType] : type;
		if (![paidTransactionTypes containsObject:combinedType]) {
			continue;
		}
		NSString *transactionCountry = transaction.countryCode;
		NSString *transactionProductID = transaction.product.productID;
		NSMutableDictionary *paidDownloadsByProduct = result[transactionCountry];
		if (!paidDownloadsByProduct) {
			paidDownloadsByProduct = [NSMutableDictionary dictionary];
			[result setObject:paidDownloadsByProduct forKey:transactionCountry];
		}
		NSInteger oldNumberOfPaidDownloads = [paidDownloadsByProduct[transactionProductID] integerValue];
		NSInteger newNumberOfPaidDownloads = oldNumberOfPaidDownloads + [transaction.units integerValue];
		[paidDownloadsByProduct setObject:@(newNumberOfPaidDownloads) forKey:transactionProductID];
	}
	return result;
}

- (NSDictionary *)totalNumberOfRefundedDownloadsByCountryAndProduct {
	NSSet *paidTransactionTypes = [[self class] combinedPaidTransactionTypes];
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	for (Transaction *transaction in self.transactions) {
		if (transaction.units.integerValue > 0) {
			continue;
		}
		NSString *type = transaction.type;
		NSString *promoType = transaction.promoType;
		if(promoType != nil) {
			promoType = [promoType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if([promoType isEqualToString:@""])promoType = nil;
		}
		NSString *combinedType = (promoType != nil) ? [NSString stringWithFormat:@"%@.%@", type, promoType] : type;
		if (![paidTransactionTypes containsObject:combinedType]) {
			continue;
		}
		NSString *transactionCountry = transaction.countryCode;
		NSString *transactionProductID = transaction.product.productID;
		NSMutableDictionary *paidDownloadsByProduct = result[transactionCountry];
		if (!paidDownloadsByProduct) {
			paidDownloadsByProduct = [NSMutableDictionary dictionary];
			[result setObject:paidDownloadsByProduct forKey:transactionCountry];
		}
		NSInteger oldNumberOfPaidDownloads = [paidDownloadsByProduct[transactionProductID] integerValue];
		NSInteger newNumberOfPaidDownloads = oldNumberOfPaidDownloads + [transaction.units integerValue];
		[paidDownloadsByProduct setObject:@(newNumberOfPaidDownloads) forKey:transactionProductID];
	}
	return result;
}

- (NSInteger)totalNumberOfPaidDownloadsForProductWithID:(NSString *)productID inCountry:(NSString *)country {
	NSSet *paidTransactionTypes = [[self class] paidTransactionTypes];
	NSInteger total = 0;
	for (Transaction *transaction in self.transactions) {
		NSString *type = transaction.type;
		if (![paidTransactionTypes containsObject:type]) {
			continue;
		}
		if (country) {
			NSString *transactionCountry = transaction.countryCode;
			if (![transactionCountry isEqualToString:country]) {
				continue;
			}
		}
		if (productID) {
			NSString *transactionProductID = transaction.product.productID;
			if (![transactionProductID isEqualToString:productID]) {
				continue;
			}
		}
		NSNumber *units = transaction.units;
		total += [units integerValue];
	}
	return total;
}

- (NSInteger)totalNumberOfPaidDownloadsForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedPaidTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfUpdatesForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedUpdateTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfRedownloadsForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedRedownloadedTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfEducationalSalesForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedEducationalTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfGiftPurchasesForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedGiftPurchaseTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfPromoCodeTransactionsForProductWithID:(NSString *)productID {
	return [self totalNumberOfTransactionsInSet:[[self class] combinedPromoCodeTransactionTypes] forProductWithID:productID];
}

- (NSInteger)totalNumberOfNewSubscriptionsForProductWithID:(NSString *)productID {
    return [self totalNumberOfSubscriptionsForProductWithID:productID subscriptionType:SubscriptionTypeNew];
}

- (NSInteger)totalNumberOfSubscriptionRenewalsForProductWithID:(NSString *)productID {
    return [self totalNumberOfSubscriptionsForProductWithID:productID subscriptionType:SubscriptionTypeRenewal];
}

- (NSInteger)totalNumberOfSubscriptionsForProductWithID:(NSString *)productID subscriptionType:(SubscriptionType)type {
    
    NSInteger total = 0;
    for (Transaction *transaction in [self subscriptionTransactions]) {
        if (transaction.subscription.type != type) { continue; }
        
        if (productID) {
            NSString *transactionProductID = transaction.product.productID;
            if (![transactionProductID isEqualToString:productID]) {
                continue;
            }
        }
        
        NSNumber *units = transaction.units;
        total += [units integerValue];
    }
    
    return total;
}

- (float)totalRevenueInBaseCurrencyForNewSubscriptionsWithProductID:(NSString *)productID {
    return [self totalSubscriptionRevenueInBaseCurrencyForProductWithID:productID subscriptionType:SubscriptionTypeNew];
}

- (float)totalRevenueInBaseCurrencyForSubscriptionRenewalsWithProductID:(NSString *)productID {
    return [self totalSubscriptionRevenueInBaseCurrencyForProductWithID:productID subscriptionType:SubscriptionTypeRenewal];
}

- (float)totalSubscriptionRevenueInBaseCurrencyForProductWithID:(NSString *)productID subscriptionType:(SubscriptionType)type {
    
    float total = 0.0;
    for (Transaction *transaction in [self subscriptionTransactions]) {
        if (transaction.subscription.type != type) { continue; }
        
        if (productID) {
            NSString *transactionProductID = transaction.product.productID;
            if (![transactionProductID isEqualToString:productID]) {
                continue;
            }
        }
        
        NSString *currency = transaction.currency;
        float transactionRevenue = [transaction.revenue floatValue];
        NSInteger transactionUnits = [transaction.units integerValue];
        
        float revenue = (transactionRevenue * transactionUnits);
        float revenueInBaseCurrency = [[CurrencyManager sharedManager] convertValue:revenue fromCurrency:currency];
        total += revenueInBaseCurrency;
    }
    return total;
}

- (NSArray<Transaction *>*)subscriptionTransactions {
    NSMutableArray *results = @[].mutableCopy;
    for (Transaction *transaction in self.transactions) {
        if (transaction.subscription == nil) { continue; }
        if (transaction.subscription.parentIdentifier == nil) { continue; }
        [results addObject:transaction];
    }
    return results;
}

- (int)totalNumberOfTransactionsInSet:(NSSet *)transactionTypes forProductWithID:(NSString *)productID {
	int total = 0;
	NSDictionary *transactionsByProduct = self.cache.content[kReportSummaryTransactions];
	if (productID) {
		NSDictionary *transactionsByType = transactionsByProduct[productID];
		for (NSString *transactionType in transactionsByType) {
			if ([transactionTypes containsObject:transactionType]) {
				total += [transactionsByType[transactionType] intValue];
			}
		}
	} else {
		for (NSString *productID in transactionsByProduct) {
			NSDictionary *transactionsByType = transactionsByProduct[productID];
			for (NSString *transactionType in transactionsByType) {
				if ([transactionTypes containsObject:transactionType]) {
					total += [transactionsByType[transactionType] intValue];
				}
			}
		}
	}
	return total;
}

// https://help.apple.com/app-store-connect/#/dev63c6f4502
//
//  1       Free or paid app - iOS, iPadOS, watchOS
//  1-B     App Bundle - iOS, iPadOS app bundle
//  F1-B    App Bundle - Mac app bundle
//  1E      Paid app - Custom iOS app
//  1EP     Paid app - Custom iPadOS app
//  1EU     Paid app - Custom universal app
//  1F      Free or paid app - Universal app, excluding tvOS
//  1T      Free or paid app - iPad apps
//  3       Re-download - App update (iOS, watchOS, tvOS)
//  3F      Re-download - Universal app, excluding tvOS
//  7       Update - App update (iOS, watchOS, tvOS)
//  7F      Update - Universal app, excluding tvOS
//  7T      Update - App update (iPadOS)
//  F1      Free or paid app - Mac
//  F7      Update - App update (Mac)
//  FI1     In-App Purchase - Mac
//  IA1     In-App Purchase - In-app purchase (iOS, iPadOS)
//  IA1-M   In-App Purchase - In-app purchase (Mac)
//  IA3     Restored In-App Purchase - Non consumable in-app purchase
//  IA9     In-App Purchase - Non-renewing subscription (iOS, iPadOS)
//  IA9-M   In-App Purchase - Subscription (Mac)
//  IAY     In-App Purchase - Auto-renewable subscription (iOS, iPadOS)
//  IAY-M   In-App Purchase - Auto-renewable subscription (Mac)

+ (NSSet *)combinedPaidTransactionTypes {
	static NSSet *combinedPaidTransactionTypes = nil;
	if (!combinedPaidTransactionTypes) {
		combinedPaidTransactionTypes = [[NSSet alloc] initWithObjects:
							@"1",		//Free or paid app - iOS, iPadOS, watchOS
							@"1. ",		//Free or paid app - iOS, iPadOS, watchOS
							@"1-B",		//App Bundle - iOS, iPadOS app bundle
							@"1-B. ",	//App Bundle - iOS, iPadOS app bundle
							@"1E",		//Paid app - Custom iOS app
							@"1E. ",	//Paid app - Custom iOS app
							@"1EP",		//Paid app - Custom iPadOS app
							@"1EP. ",	//Paid app - Custom iPadOS app
							@"1EU",		//Paid app - Custom universal app
							@"1EU. ",	//Paid app - Custom universal app
							@"1F",		//Free or paid app - Universal app, excluding tvOS
							@"1F. ",	//Free or paid app - Universal app, excluding tvOS
							@"1T",		//Free or paid app - iPad apps
							@"1T. ",	//Free or paid app - iPad apps
							@"F1",		//Free or paid app - Mac
							@"F1. ",	//Free or paid app - Mac
							@"F1-B",	//App Bundle - Mac app bundle
							@"F1-B. ",	//App Bundle - Mac app bundle
							@"FI1",		//In-App Purchase - Mac
							@"FI1. ",	//In-App Purchase - Mac
							@"IA1-M",	//In-App Purchase - In-app purchase (Mac)
							@"IA1-M. ",	//In-App Purchase - In-app purchase (Mac)
							@"IA1",		//In-App Purchase - In-app purchase (iOS, iPadOS)
							@"IA1. ",	//In-App Purchase - In-app purchase (iOS, iPadOS)
							@"IA9",		//In-App Purchase - Non-renewing subscription (iOS, iPadOS)
							@"IA9. ",	//In-App Purchase - Non-renewing subscription (iOS, iPadOS)
							@"IA9-M",	//In-App Purchase - Subscription (Mac)
							@"IA9-M. ",	//In-App Purchase - Subscription (Mac)
							@"IAY",		//In-App Purchase - Auto-renewable subscription (iOS, iPadOS)
							@"IAY. ",	//In-App Purchase - Auto-renewable subscription (iOS, iPadOS)
							@"IAY-M",	//In-App Purchase - Auto-renewable subscription (Mac)
							@"IAY-M. ",	//In-App Purchase - Auto-renewable subscription (Mac)
							@"IAC",		//In-App Free Subscription
							@"IAC. "	//In-App Free Subscription
							@"1.GP",	//GP = Gift Purchase
							@"1F.GP",
							@"1T.GP",
							@"F1.GP",
							@"IA1.GP",
							@"IA9.GP",
							@"1.EDU",	//EDU = Education Store transaction
							@"1F.EDU",
							@"1T.EDU",
							@"F1.EDU",
							@"IA1.EDU",
							@"IA9.EDU",
							nil];
	}
	return combinedPaidTransactionTypes;
}

+ (NSSet *)combinedUpdateTransactionTypes {
	static NSSet *combinedUpdateTransactionTypes = nil;
	if (!combinedUpdateTransactionTypes) {
		combinedUpdateTransactionTypes = [[NSSet alloc] initWithObjects:
										@"7",		//Update - App update (iOS, watchOS, tvOS)
										@"7F",		//Update - Universal app, excluding tvOS
										@"7T",		//Update - App update (iPadOS)
										@"F7",		//Update - App update (Mac)
										@"7.GP",	//GP = Gift Purchase
										@"7F.GP",
										@"7T.GP",
										@"F7.GP",
										@"7.EDU",	//EDU = Education Store transaction
										@"7F.EDU",
										@"7T.EDU",
										@"F7.EDU",
										nil];
	}
	return combinedUpdateTransactionTypes;
}

+ (NSSet *)combinedRedownloadedTransactionTypes {
	static NSSet *combinedRedownloadedTransactionTypes = nil;
	if (!combinedRedownloadedTransactionTypes) {
		combinedRedownloadedTransactionTypes = [[NSSet alloc] initWithObjects:
												@"3",   //Re-download - App update (iOS, watchOS, tvOS)
												@"3F",  //Re-download - Universal app, excluding tvOS
												@"3T",
												@"F3",
												nil];
	}
	return combinedRedownloadedTransactionTypes;
}

+ (NSSet *)combinedEducationalTransactionTypes {
	static NSSet *combinedEducationalTransactionTypes = nil;
	if (!combinedEducationalTransactionTypes) {
		combinedEducationalTransactionTypes = [[NSSet alloc] initWithObjects:
										@"1.EDU",
										@"1F.EDU",
										@"1T.EDU",
										@"F1.EDU",
										@"IA1.EDU",
										@"IA9.EDU",
										@"IAY.EDU",
										@"FI1.EDU",
										@"1E.EDU",
										@"1EP.EDU",
										@"1EU.EDU",
										@"1-B.EDU",
										@"F1-B.EDU",
										nil];
	}
	return combinedEducationalTransactionTypes;
}

+ (NSSet *)combinedGiftPurchaseTransactionTypes {
	static NSSet *combinedGiftPurchaseTransactionTypes = nil;
	if (!combinedGiftPurchaseTransactionTypes) {
		combinedGiftPurchaseTransactionTypes = [[NSSet alloc] initWithObjects:
										@"1.GP",	//GP = Gift Purchase
										@"1F.GP",
										@"1T.GP",
										@"F1.GP",
										@"IA1.GP",
										@"IA9.GP",
										@"IAY.GP",
										@"FI1.GP",
										@"1E.GP",
										@"1EP.GP",
										@"1EU.GP",
										@"1-B.GP",
										@"F1-B.GP",
										nil];
	}
	return combinedGiftPurchaseTransactionTypes;
}

+ (NSSet *)combinedPromoCodeTransactionTypes {
	static NSSet *combinedPromoCodeTransactionTypes = nil;
	if (!combinedPromoCodeTransactionTypes) {
		combinedPromoCodeTransactionTypes = [[NSSet alloc] initWithObjects:
												@"1.CR-RW",
												@"1F.CR-RW",
												@"1T.CR-RW",
												@"F1.CR-RW",
												@"IA1.CR-RW",
												@"IA9.CR-RW",
												@"IAY.CR-RW",
												@"FI1.CR-RW",
												@"1E.CR-RW",
												@"1EP.CR-RW",
												@"1EU.CR-RW",
												@"1-B.CR-RW",
												@"F1-B.CR-RW",
												nil];
	}
	return combinedPromoCodeTransactionTypes;
}

+ (NSSet *)paidTransactionTypes {
	static NSSet *paidTransactionTypes = nil;
	if (!paidTransactionTypes) {
		paidTransactionTypes = [[NSSet alloc] initWithObjects:
								@"1",		//iPhone App
								@"1F",		//Universal App
								@"1T",		//iPad App
								@"F1",		//Mac App
								@"IA1",		//In-App Purchase
								@"IA9",		//In-App Subscription
								@"IA9-M",	//In-App Subscription (Mac)
								@"IAY",		//In-App Auto-Renewable Subscription
								@"IAY-M",	//In-App Auto-Renewable Subscription (Mac)
								@"FI1",		//Mac In-App Purchase
								@"IA1-M",	//Mac In-App Purchase
								@"1E",		//Paid App (Custom iPhone)
								@"1EP",		//Paid App (Custom iPad)
								@"1EU",		//Paid App (Custom Universal)
								@"1-B",		//App Bundle
								@"F1-B",	//Mac App Bundle
								nil];
	}
	return paidTransactionTypes;
}

- (NSDictionary *)revenueInBaseCurrencyByCountry {
	return [self revenueInBaseCurrencyByCountryForProductWithID:nil];
}

- (NSDictionary *)revenueInBaseCurrencyByCountryForProductWithID:(NSString *)productID {
	NSMutableDictionary *revenueByCountry = [NSMutableDictionary dictionary];
	for (Transaction *transaction in self.transactions) {
		if (productID && ![transaction.product.productID isEqualToString:productID]) {
			continue;
		}
		float revenue = [transaction.revenue floatValue];
		NSString *currency = transaction.currency;
		int units = [transaction.units intValue];
		float revenueInBaseCurrency = [[CurrencyManager sharedManager] convertValue:(revenue * units) fromCurrency:currency];
		NSString *country = transaction.countryCode;
		float oldRevenue = [revenueByCountry[country] floatValue];
		float newRevenue = oldRevenue + revenueInBaseCurrency;
		[revenueByCountry setObject:@(newRevenue) forKey:country];
	}
	return revenueByCountry;
}

- (Report *)firstReport {
	//ReportSummary protocol method, allows us to treat "virtual" reports (like months) the same as actual reports in many situations.
	return self;
}

- (NSArray *)allReports {
	//ReportSummary protocol method, allows us to treat "virtual" reports (like months) the same as actual reports in many situations.
	return @[self];
}

- (NSString *)title {
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	return [dateFormatter stringFromDate:self.startDate];
}

+ (NSDate *)dateFromReportDateString:(NSString *)dateString {
	dateString = [dateString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	BOOL containsSlash = [dateString rangeOfString:@"/"].location != NSNotFound;
	int year, month, day;
	if (!containsSlash && [dateString length] == 8) {
		//old date format
		year = [[dateString substringWithRange:NSMakeRange(0, 4)] intValue];
		month = [[dateString substringWithRange:NSMakeRange(4, 2)] intValue];
		day = [[dateString substringWithRange:NSMakeRange(6, 2)] intValue];
	} else if (containsSlash && [dateString length] == 10) {
		// new date format
		year = [[dateString substringWithRange:NSMakeRange(6, 4)] intValue];
		month = [[dateString substringWithRange:NSMakeRange(0, 2)] intValue];
		day = [[dateString substringWithRange:NSMakeRange(3, 2)] intValue];
	} else {
		return nil;
	}
	
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setYear:year];
	[components setMonth:month];
	[components setDay:day];
	NSDate *date = [calendar dateFromComponents:components];
	return date;
}

+ (NSString *)identifierForDate:(NSDate *)date {
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"MM/dd/yyyy"];
	[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	NSString *reportIdentifier = [formatter stringFromDate:date];
	return reportIdentifier;
}

@end
