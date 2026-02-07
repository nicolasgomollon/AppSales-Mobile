//
//  AppleFiscalCalendar.m
//  AppSales
//
//  Created by Tim Shadel on 4/5/11.
//  Copyright 2011 Shadel Software, Inc. All rights reserved.
//

#import "AppleFiscalCalendar.h"

@implementation AppleFiscalCalendar

static NSDate *LastSundayOfSeptemberForYear(NSCalendar *calendar, NSInteger year) {
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setYear:year];
	[components setMonth:9];
	[components setDay:30];
	NSDate *lastDayOfSeptember = [calendar dateFromComponents:components];
	NSDateComponents *weekday = [calendar components:NSCalendarUnitWeekday fromDate:lastDayOfSeptember];
	NSInteger weekdayIndex = [weekday weekday]; // 1=Sunday ... 7=Saturday
	NSInteger daysToSubtract = (weekdayIndex == 1) ? 0 : (weekdayIndex - 1);
	return [lastDayOfSeptember dateByAddingTimeInterval:-daysToSubtract * 24 * 60 * 60];
}

static NSDate *FiscalYearStartForDate(NSCalendar *calendar, NSDate *date) {
	NSDateComponents *components = [calendar components:NSCalendarUnitYear fromDate:date];
	NSInteger year = [components year];
	NSDate *fyStart = LastSundayOfSeptemberForYear(calendar, year);
	if ([date compare:fyStart] == NSOrderedAscending) {
		fyStart = LastSundayOfSeptemberForYear(calendar, year - 1);
	}
	return fyStart;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		
		NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		NSDateComponents *firstDateComponents = [[NSDateComponents alloc] init];
		[firstDateComponents setMonth:9];
		[firstDateComponents setDay:30];
		[firstDateComponents setYear:2007];
		NSDate *firstDate = [calendar dateFromComponents:firstDateComponents];
		
		NSDateComponents *components5Weeks = [[NSDateComponents alloc] init];
		[components5Weeks setWeekOfMonth:5];
		NSDateComponents *components4Weeks = [[NSDateComponents alloc] init];
		[components4Weeks setWeekOfMonth:4];
		
		NSMutableArray *dates = [NSMutableArray array];
		NSDate *currentDate = firstDate;
		int period = 0;
		
		NSDate *now = [NSDate date];
		
		// Covers fiscal calendar from 2008 to one period after the current fiscal period.
		while ([currentDate earlierDate:now] == currentDate || [currentDate isEqualToDate:now]) {
			
			NSDate *fyStart = FiscalYearStartForDate(calendar, currentDate);
			NSDateComponents *currentYear = [calendar components:NSCalendarUnitYear fromDate:fyStart];
			NSDate *nextFyStart = LastSundayOfSeptemberForYear(calendar, [currentYear year] + 1);
			NSInteger fyLengthDays = [calendar components:NSCalendarUnitDay fromDate:fyStart toDate:nextFyStart options:0].day;
			BOOL is53WeekYear = (fyLengthDays == 371);

			NSInteger daysSinceFyStart = [calendar components:NSCalendarUnitDay fromDate:fyStart toDate:currentDate options:0].day;
			NSInteger weeksSinceFyStart = daysSinceFyStart / 7;
			NSInteger monthWeeks[12] = {5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4};
			if (is53WeekYear) {
				// Add the extra week to the last month of Q1 (December).
				monthWeeks[2] = 5;
			}

			NSInteger periodInYear = 0;
			NSInteger cumulativeWeeks = 0;
			for (NSInteger i = 0; i < 12; i++) {
				if (weeksSinceFyStart == cumulativeWeeks) {
					periodInYear = i;
					break;
				}
				cumulativeWeeks += monthWeeks[i];
			}

			BOOL isFiveWeekPeriod = (monthWeeks[periodInYear] == 5);
			NSDate *nextDate = [calendar dateByAddingComponents:(isFiveWeekPeriod ? components5Weeks : components4Weeks) toDate:currentDate options:0];
			
			[dates addObject:nextDate];
			currentDate = nextDate;
			period++;
		}
		
		NSMutableArray *names = [NSMutableArray array];
		
		NSDateFormatter *sectionTitleFormatter = [NSDateFormatter new];
		[sectionTitleFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[sectionTitleFormatter setDateFormat:@"MMMM yyyy"];
		
		for (NSDate *date in dates) {
			// Name of the fiscal month can be reliably found by the calendar month of a day 2 weeks after the fiscal month begins
			NSDateComponents *components = [NSDateComponents new];
			[components setDay:14];
			NSDate *result = [calendar dateByAddingComponents:components toDate:date options:0];
			NSString *fiscalMonthName = [sectionTitleFormatter stringFromDate:result];
			[names addObject:fiscalMonthName];
		}
		sortedFiscalMonthNames = [[NSArray alloc] initWithArray:names];
		sortedDates = [[NSArray alloc] initWithArray:dates];
	}
	return self;
}

- (NSString *)fiscalMonthForDate:(NSDate *)requestedDate {
	NSUInteger indexOfNextMonth = [self indexOfNextMonthForDate:requestedDate];
	if (indexOfNextMonth > 0) {
		return sortedFiscalMonthNames[indexOfNextMonth - 1];
	} else {
		return nil;
	}
}

- (NSDate *)representativeDateForFiscalMonthOfDate:(NSDate *)requestedDate {
	NSUInteger indexOfNextMonth = [self indexOfNextMonthForDate:requestedDate];
	if (indexOfNextMonth > 0) {
		NSDate *startOfFiscalMonth = sortedDates[indexOfNextMonth - 1];
		NSDate *representativeDate = [startOfFiscalMonth dateByAddingTimeInterval:14 * 24 * 60 * 60];
		return representativeDate;
	} else {
		return nil;
	}
}

- (NSUInteger)indexOfNextMonthForDate:(NSDate *)requestedDate {
	NSUInteger indexOfNextMonth = [sortedDates indexOfObject:requestedDate 
											   inSortedRange:NSMakeRange(0, [sortedDates count])
													 options:NSBinarySearchingLastEqual|NSBinarySearchingInsertionIndex
											 usingComparator:^ (id obj1, id obj2) {
												 // Treat equality as ascending so that month start dates map to the new month,
												 // and insertion index points to the next month (we'll subtract one).
												 return [obj1 compare:obj2] == NSOrderedDescending ? NSOrderedDescending : NSOrderedAscending;
											 }];
	
	return indexOfNextMonth;
}

+ (AppleFiscalCalendar *)sharedFiscalCalendar {
	static id sharedFiscalCalendar = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedFiscalCalendar = [[self alloc] init];
	});
	return sharedFiscalCalendar;
}



@end
