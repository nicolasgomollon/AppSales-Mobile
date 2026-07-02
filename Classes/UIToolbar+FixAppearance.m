//
//  UIToolbar+FixAppearance.m
//  AppSales
//
//  Created by Darren Jones on 09/06/2022.
//  Copyright © 2022 omz:software. All rights reserved.
//

#import "UIToolbar+FixAppearance.h"

@implementation UIToolbar (FixAppearance)

+ (void)fixToolbarAppearance {
    UIToolbarAppearance *newAppearance = [[UIToolbarAppearance alloc] init];
    [newAppearance configureWithOpaqueBackground];
    UIToolbar *appearance = [UIToolbar appearance];
    appearance.compactAppearance = newAppearance;
    appearance.standardAppearance = newAppearance;
    if (@available(iOS 15.0, *)) {
        appearance.scrollEdgeAppearance = newAppearance;
        appearance.compactScrollEdgeAppearance = newAppearance;
    }
}

@end
