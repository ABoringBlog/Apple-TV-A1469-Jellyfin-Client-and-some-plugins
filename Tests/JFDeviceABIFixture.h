#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "BackRow/JFBRMenu.h"
#import "BackRow/JFUIController.h"
// Host fixture generated from audited contracts; not a private SDK header.
static int categoryCalls;
static float categoryOrder;
@interface JFDeviceCategoryFixture : NSObject
+ (id)categoryWithName:(id)name identifier:(id)identifier preferredOrder:(float)order;
@end
@implementation JFDeviceCategoryFixture
+ (id)categoryWithName:(id)name identifier:(id)identifier preferredOrder:(float)order {
    categoryCalls++; categoryOrder=order;
    return @{ @"name":name, @"identifier":identifier, @"order":@(order) };
}
@end
static void JFRegisterCategoryFixture(void) {
    objc_registerClassPair(objc_allocateClassPair([JFDeviceCategoryFixture class],"BRApplianceCategory",0));
}
static __attribute__((unused)) void JFRegisterProtocolFixture(const char *name, Class cls, NSArray *selectors) {
    Protocol *p=objc_allocateProtocol(name);
    for (NSString *s in selectors) {
        SEL sel=NSSelectorFromString(s);
        protocol_addMethodDescription(p,sel,method_getTypeEncoding(class_getInstanceMethod(cls,sel)),YES,YES);
    }
    objc_registerProtocol(p);
}
