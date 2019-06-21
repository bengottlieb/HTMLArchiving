//
//  CSSParser.h
//

#import <Foundation/Foundation.h>

@interface CSSParser : NSObject

+ (instancetype) parser;

- (NSDictionary *) parseText: (NSString *) cssText;

@end
