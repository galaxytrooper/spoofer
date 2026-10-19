//
//  Spoof.m — SpoofLite v1.1
//  Dylib universal spoof tool for iOS. Injectable into any app. No jailbreak required.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>

#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

#pragma mark - Estado / Config

static NSString *const kStateFile = @"spooflite.state";   // dentro de Documents
static NSMutableDictionary *gState = nil;
static NSObject *gLock = nil;
static NSArray *gProfile = nil;
static NSString *gRealMachine = nil;

static NSDictionary *cfg(void){
    static NSDictionary *c; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSMutableDictionary *m = [NSMutableDictionary new];
        // 1) spoof.plist dentro de la app (Payload/App.app/spoof.plist)
        NSString *bp = [[NSBundle mainBundle] pathForResource:@"spoof" ofType:@"plist"];
        if (bp){ NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:bp]; if (d) [m addEntriesFromDictionary:d]; }
        // 2) spoof.plist en Documents (tiene prioridad, editable sin recompilar)
        NSString *dp = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/spoof.plist"];
        NSDictionary *d2 = [NSDictionary dictionaryWithContentsOfFile:dp];
        if (d2) [m addEntriesFromDictionary:d2];
        c = m;
    });
    return c;
}
static BOOL cfgBool(NSString *k, BOOL d){ id v = cfg()[k]; return v ? [v boolValue] : d; }
static NSString *cfgStr(NSString *k){ id v = cfg()[k]; return [v isKindOfClass:[NSString class]] && [v length] ? v : nil; }

static NSString *StatePath(void){
    static NSString *p; static dispatch_once_t o;
    dispatch_once(&o, ^{ p = [NSHomeDirectory() stringByAppendingPathComponent:
                              [@"Documents" stringByAppendingPathComponent:kStateFile]]; });
    return p;
}
static void stateLoad(void){
    if (gState) return;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:StatePath()];
    gState = [d isKindOfClass:[NSDictionary class]] ? [d mutableCopy] : [NSMutableDictionary new];
}
static void stateSave(void){ [gState writeToFile:StatePath() atomically:YES]; }

static NSString *ident(NSString *key, NSString *(^gen)(void)){
    @synchronized(gLock){
        NSString *ov = cfgStr(key);
        if (ov) return ov;
        if (cfgBool(@"rotateEveryLaunch", NO)) return gen ? gen() : @"";
        stateLoad();
        id v = gState[key];
        if ([v isKindOfClass:[NSString class]] && [(NSString*)v length]) return v;
        NSString *n = gen ? gen() : @"";
        gState[key] = n; stateSave();
        return n;
    }
}

#pragma mark - Aleatorios / perfiles

static NSString *rndUUID(void){ return [[NSUUID UUID] UUIDString]; }
static id pick(NSArray *a){ return a[arc4random_uniform((uint32_t)a.count)]; }

static NSArray *iPhonePool(void){
    return @[ @[@"iPhone14,5",@"D16AP", @390,@844, @3],
              @[@"iPhone14,2",@"D63AP", @390,@844, @3],
              @[@"iPhone14,3",@"D64AP", @428,@926, @3],
              @[@"iPhone15,4",@"D37AP", @393,@852, @3],
              @[@"iPhone15,5",@"D38AP", @430,@932, @3],
              @[@"iPhone15,2",@"D73AP", @393,@852, @3],
              @[@"iPhone15,3",@"D74AP", @430,@932, @3],
              @[@"iPhone16,1",@"D83AP", @393,@852, @3],
              @[@"iPhone16,2",@"D84AP", @430,@932, @3],
              @[@"iPhone17,3",@"D47AP", @402,@874, @3],
              @[@"iPhone17,1",@"D94AP", @402,@874, @3] ];
}
static NSArray *iPadPool(void){
    return @[ @[@"iPad13,4",@"J517AP", @820,@1180, @2],
              @[@"iPad13,8",@"J522AP", @834,@1194, @2],
              @[@"iPad14,3",@"J617AP", @834,@1194, @2] ];
}
static NSArray *currentProfile(void){
    NSArray *pool = (gRealMachine && [gRealMachine hasPrefix:@"iPad"]) ? iPadPool() : iPhonePool();
    if (cfgBool(@"rotateEveryLaunch", NO)){
        if (!gProfile) gProfile = pick(pool);
        return gProfile;
    }
    @synchronized(gLock){
        stateLoad();
        NSNumber *idx = gState[@"profileIdx"];
        if (![idx isKindOfClass:[NSNumber class]]){
            idx = @(arc4random_uniform((uint32_t)pool.count));
            gState[@"profileIdx"] = idx; stateSave();
        }
        return pool[idx.unsignedIntegerValue % pool.count];
    }
}
static NSString *machineName(void){ NSString *o = cfgStr(@"machine"); return o ?: currentProfile()[0]; }
static NSString *boardName(void){   NSString *o = cfgStr(@"board");   return o ?: currentProfile()[1]; }
static NSString *deviceName(void){
    return ident(@"deviceName", ^{
        return pick(@[@"iPhone", @"iPhone de Alex", @"iPhone de Ana", @"iPhone de Luis",
                      @"iPhone de Marta", @"iPhone nuevo", @"iPhone de Javi"]);
    });
}
static NSString *hostNameSpoof(void){ return ident(@"hostName", ^{ return deviceName(); }); }

#pragma mark - Swizzling

static void swizI(Class c, SEL a, SEL b){
    if (!c) return;
    Method m1 = class_getInstanceMethod(c,a), m2 = class_getInstanceMethod(c,b);
    if (m1 && m2) method_exchangeImplementations(m1,m2);
}
static void swizC(Class c, SEL a, SEL b){
    if (!c) return;
    Method m1 = class_getClassMethod(c,a), m2 = class_getClassMethod(c,b);
    if (m1 && m2) method_exchangeImplementations(m1,m2);
}

#pragma mark - Hooks ObjC

@implementation UIDevice (SpoofLite)
- (NSUUID *)sl_identifierForVendor {
    if (!cfgBool(@"spoofIDFV", YES)) return [self sl_identifierForVendor];
    return [[NSUUID alloc] initWithUUIDString:ident(@"idfv", ^{ return rndUUID(); })] ?: [NSUUID UUID];
}
- (NSString *)sl_name {
    if (!cfgBool(@"spoofName", YES)) return [self sl_name];
    return deviceName();
}
- (NSString *)sl_model {
    NSString *real = [self sl_model];
    NSString *base = [real hasPrefix:@"iPad"] ? @"iPad" : @"iPhone";
    return cfgStr(@"model") ?: base;
}
- (NSString *)sl_localizedModel { return [self sl_model]; }
- (NSString *)sl_systemVersion {
    NSString *o = cfgStr(@"systemVersion");
    return o ? o : [self sl_systemVersion];
}
@end

@implementation ASIdentifierManager (SpoofLite)
- (NSUUID *)sl_advertisingIdentifier {
    if (!cfgBool(@"spoofIDFA", YES)) return [self sl_advertisingIdentifier];
    return [[NSUUID alloc] initWithUUIDString:ident(@"idfa", ^{ return rndUUID(); })] ?: [NSUUID UUID];
}
- (BOOL)sl_isAdvertisingTrackingEnabled { return YES; }
@end

@implementation ATTrackingManager (SpoofLite)
+ (NSUInteger)sl_authorizationStatus { return 3; }
+ (void)sl_requestTrackingAuthorizationWithCompletionHandler:(void(^)(NSUInteger))cb {
    if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(3); });
}
@end

@implementation NSProcessInfo (SpoofLite)
- (NSString *)sl_hostName { return hostNameSpoof(); }
@end

@implementation CTCarrier (SpoofLite)
- (NSString *)sl_carrierName {
    NSArray *c = @[ @[@"Movistar",@"214",@"07",@"es"], @[@"Vodafone",@"214",@"01",@"es"],
                    @[@"Orange",@"214",@"03",@"es"],  @[@"T-Mobile",@"310",@"260",@"us"],
                    @[@"Telekom",@"262",@"01",@"de"] ];
    return cfgStr(@"carrierName") ?: pick(c)[0];
}
- (NSString *)sl_mobileCountryCode { return pick(@[@"214",@"310",@"262"]); }
- (NSString *)sl_mobileNetworkCode { return pick(@[@"07",@"260",@"01"]); }
- (NSString *)sl_isoCountryCode { return cfgStr(@"carrierISO") ?: @"es"; }
@end

@implementation UIScreen (SpoofLite)
- (CGRect)sl_bounds {
    if (!cfgBool(@"spoofScreen", NO)) return [self sl_bounds];
    NSArray *p = currentProfile();
    return CGRectMake(0,0,[p[2] doubleValue],[p[3] doubleValue]);
}
- (CGRect)sl_nativeBounds {
    if (!cfgBool(@"spoofScreen", NO)) return [self sl_nativeBounds];
    NSArray *p = currentProfile(); double s = [p[4] doubleValue];
    return CGRectMake(0,0,[p[2] doubleValue]*s,[p[3] doubleValue]*s);
}
- (CGFloat)sl_scale { return cfgBool(@"spoofScreen", NO) ? [currentProfile()[4] doubleValue] : [self sl_scale]; }
- (CGFloat)sl_nativeScale { return cfgBool(@"spoofScreen", NO) ? [currentProfile()[4] doubleValue] : [self sl_nativeScale]; }
@end

#pragma mark - Hooks C (dyld interpose)

static int (*orig_uname)(struct utsname *);
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_gethostname)(char *, size_t);

static void copyStr(void *dst, size_t *lenp, NSString *s){
    if (!dst) { if (lenp) *lenp = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1; return; }
    const char *c = [s UTF8String];
    size_t need = strlen(c) + 1, cap = lenp ? *lenp : need;
    if (cap > 0){ size_t n = need < cap ? need : cap; memcpy(dst, c, n); ((char*)dst)[n-1] = 0; }
    if (lenp) *lenp = need;
}
static int my_uname(struct utsname *u){
    int r = orig_uname(u);
    if (r == 0){ copyStr(u->machine, NULL, machineName()); copyStr(u->nodename, NULL, hostNameSpoof()); }
    return r;
}
static int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen){
    if (oldp && !newp){
        if (!strcmp(name,"hw.machine"))   { copyStr(oldp, oldlenp, machineName());   return 0; }
        if (!strcmp(name,"hw.model"))     { copyStr(oldp, oldlenp, boardName());     return 0; }
        if (!strcmp(name,"kern.hostname")){ copyStr(oldp, oldlenp, hostNameSpoof()); return 0; }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}
static int my_sysctl(int *name, u_int nl, void *oldp, size_t *oldlenp, void *newp, size_t newlen){
    if (oldp && !newp && nl >= 2){
        if (name[0]==CTL_HW && name[1]==HW_MACHINE){ copyStr(oldp, oldlenp, machineName()); return 0; }
        if (name[0]==CTL_HW && name[1]==HW_MODEL)  { copyStr(oldp, oldlenp, boardName());   return 0; }
    }
    return orig_sysctl(name, nl, oldp, oldlenp, newp, newlen);
}
static int my_gethostname(char *n, size_t l){
    NSString *h = hostNameSpoof();
    if (n){ const char *c = [h UTF8String]; size_t need = strlen(c)+1; if (need > l) need = l; memcpy(n, c, need); n[need-1] = 0; }
    return 0;
}

#define DYLD_INTERPOSE(_rep,_orig) \
    __attribute__((used)) static struct { const void *rep; const void *orig; } \
    _interpose_##_orig __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_rep, (const void *)(unsigned long)&_orig };

 DYLD_INTERPOSE(my_uname, uname)
 DYLD_INTERPOSE(my_sysctlbyname, sysctlbyname)
 DYLD_INTERPOSE(my_sysctl, sysctl)
 DYLD_INTERPOSE(my_gethostname, gethostname)

#pragma mark - Instalación

__attribute__((constructor)) static void spooflite_init(void){
    gLock = [NSObject new];

   // struct utsname u; if (uname(&u)==0) gRealMachine = [NSString stringWithUTF8String:u.machine];

    swizI([UIDevice class], @selector(identifierForVendor), @selector(sl_identifierForVendor));
    swizI([UIDevice class], @selector(name),               @selector(sl_name));
    swizI([UIDevice class], @selector(model),              @selector(sl_model));
    swizI([UIDevice class], @selector(localizedModel),     @selector(sl_localizedModel));
    swizI([UIDevice class], @selector(systemVersion),      @selector(sl_systemVersion));

    if (NSClassFromString(@"ASIdentifierManager")){
        swizI(NSClassFromString(@"ASIdentifierManager"), @selector(advertisingIdentifier), @selector(sl_advertisingIdentifier));
        swizI(NSClassFromString(@"ASIdentifierManager"), @selector(isAdvertisingTrackingEnabled), @selector(sl_isAdvertisingTrackingEnabled));
    }
    if (NSClassFromString(@"ATTrackingManager")){
        swizC(NSClassFromString(@"ATTrackingManager"), @selector(authorizationStatus), @selector(sl_authorizationStatus));
        swizC(NSClassFromString(@"ATTrackingManager"), @selector(requestTrackingAuthorizationWithCompletionHandler:),
              @selector(sl_requestTrackingAuthorizationWithCompletionHandler:));
    }
    swizI([NSProcessInfo class], @selector(hostName), @selector(sl_hostName));
    if (NSClassFromString(@"CTCarrier")){
        swizI(NSClassFromString(@"CTCarrier"), @selector(carrierName),       @selector(sl_carrierName));
        swizI(NSClassFromString(@"CTCarrier"), @selector(mobileCountryCode), @selector(sl_mobileCountryCode));
        swizI(NSClassFromString(@"CTCarrier"), @selector(mobileNetworkCode), @selector(sl_mobileNetworkCode));
        swizI(NSClassFromString(@"CTCarrier"), @selector(isoCountryCode),    @selector(sl_isoCountryCode));
    }
    if (cfgBool(@"spoofScreen", NO)){
        swizI([UIScreen class], @selector(bounds),       @selector(sl_bounds));
        swizI([UIScreen class], @selector(nativeBounds), @selector(sl_nativeBounds));
        swizI([UIScreen class], @selector(scale),        @selector(sl_scale));
        swizI([UIScreen class], @selector(nativeScale),  @selector(sl_nativeScale));
    }

    NSLog(@"[SpoofLite] activo · idfv=%@ · machine=%@ · real=%@",
          ident(@"idfv", ^{ return rndUUID(); }), machineName(), gRealMachine);
}
