//  HTMLElement.m
//
//  Public domain. https://github.com/nolanw/HTMLReader

#import "HTMLElement.h"
#import "HTMLOrderedDictionary.h"
#import "HTMLSelector.h"
#import "CSSParser.h"

NS_ASSUME_NONNULL_BEGIN

@implementation HTMLElement
{
    HTMLOrderedDictionary *_attributes;
}

- (instancetype)initWithTagName:(NSString *)tagName attributes:(HTMLDictOf(NSString *, NSString *) * __nullable)attributes
{
    NSParameterAssert(tagName);
    
    if ((self = [super init])) {
        _tagName = [tagName copy];
        _attributes = [HTMLOrderedDictionary new];
        if (attributes) {
            [_attributes addEntriesFromDictionary:(NSDictionary * __nonnull)attributes];
        }
    }
    return self;
}

- (instancetype)init
{
    return [self initWithTagName:@"" attributes:nil];
}

- (HTMLDictOf(NSString *, NSString *) *)attributes
{
    return [_attributes copy];
}

- (id __nullable)objectForKeyedSubscript:(id)attributeName
{
    return _attributes[attributeName];
}

- (void)setObject:(NSString *)attributeValue forKeyedSubscript:(NSString *)attributeName
{
    NSParameterAssert(attributeValue);
    
    _attributes[attributeName] = attributeValue;
}

- (void)removeAttributeWithName:(NSString *)attributeName
{
    [_attributes removeObjectForKey:attributeName];
}

- (BOOL)hasClass:(NSString *)className
{
    NSParameterAssert(className);
    
    NSArray *classes = [self[@"class"] componentsSeparatedByCharactersInSet:HTMLSelectorWhitespaceCharacterSet()];
    return [classes containsObject:className];
}

- (void)toggleClass:(NSString *)className
{
    NSParameterAssert(className);
    
    NSString *classValue = self[@"class"] ?: @"";
    NSMutableArray *classes = [[classValue componentsSeparatedByCharactersInSet:HTMLSelectorWhitespaceCharacterSet()] mutableCopy];
    NSUInteger i = [classes indexOfObject:className];
    if (i == NSNotFound) {
        [classes addObject:className];
    } else {
        [classes removeObjectAtIndex:i];
    }
    self[@"class"] = [classes componentsJoinedByString:@" "];
}

- (NSURL * _Nullable) resourceURLBasedOn: (NSURL * _Nullable) base {
	NSString		*raw = self.attributes[@"href"] ?: self.attributes[@"src"];
	
	if (raw == nil) return nil;
	
	NSURL			*result = [NSURL URLWithString: raw relativeToURL: base];
	NSString		*scheme = result.scheme;
	
	if ([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"]) { return result; }
	return nil;
}

- (NSDictionary *) parsedStyleTag {
	NSString			*raw = self.attributes[@"style"];
	
	if (raw == nil) { return @{}; }
	
	NSString			*framed = [raw hasPrefix: @"{"] ? raw : [NSString stringWithFormat: @"{%@}", raw];
	NSDictionary		*allResults = [[CSSParser parser] parseText: framed];
	NSMutableDictionary	*combined = [NSMutableDictionary dictionary];
	
	for (NSString *key in allResults) {
		NSDictionary		*value = allResults[key];
		
		if ([value isKindOfClass: [NSDictionary class]]) {
			[combined addEntriesFromDictionary: value];
		}
	}
	return combined;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone * __nullable)zone
{
    HTMLElement *copy = [super copyWithZone:zone];
    copy->_tagName = self.tagName;
    copy->_attributes = [_attributes copy];
    return copy;
}

@end

NS_ASSUME_NONNULL_END
