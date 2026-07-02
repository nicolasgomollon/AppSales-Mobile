//
//  UINavigationBar+FixBarColor.m
//  AppSales
//
//  Created by Darren Jones on 08/06/2022.
//  Copyright © 2022 omz:software. All rights reserved.
//

#import "UINavigationBar+FixAppearance.h"

@implementation UINavigationBar (FixBarColor)

/**
 iOS 15 caused the navigation bar to appear black (see through with no background color).
 */
+ (void)fixNavigationBarAppearance {
    UINavigationBarAppearance *newAppearance = [[UINavigationBarAppearance alloc] init];
    [newAppearance configureWithOpaqueBackground];
    UINavigationBar *appearance = [UINavigationBar appearance];
    appearance.scrollEdgeAppearance = newAppearance;
    appearance.compactAppearance = newAppearance;
    appearance.standardAppearance = newAppearance;
    if (@available(iOS 15.0, *)) {
        appearance.compactScrollEdgeAppearance = newAppearance;
    }
}

@end
