// MomentsTagFilter — 朋友圈按好友标签分类筛选
//
// Copyright (c) 2026 MomentsTagFilter contributors.
// Licensed under the MIT License. See the LICENSE file for details.
//
// 免责声明 / DISCLAIMER
//   本软件按「现状」提供，不含任何明示或默示担保。
//   本项目仅供个人学习、技术研究与合法的互操作性研究之用。
//   使用者须自行遵守所在国家/地区的法律法规，以及相关软件的用户协议与条款。
//   严禁将本软件用于任何违法、侵权、破坏数据安全或损害他人合法权益的用途。
//   因使用或无法使用本软件造成的任何风险与后果（包括但不限于账号受限、
//   数据丢失、服务中断）均由使用者自行承担，作者与贡献者不承担任何责任。
//   本项目为独立的第三方开源项目，与任何第三方应用的开发者或权利人均无隶属、
//   赞助或背书关系，所涉第三方名称、商标归其各自权利人所有。
//
// 功能概述
//   入口一：在「第三方插件管理」中注册设置页（启用开关 + 标签多选）。
//   入口二：启用后，在朋友圈页提供悬浮筛选入口，按好友标签过滤信息流。
//   过滤方式：对数据门面的条目计数与取值做「过滤投影」，仅保留作者属于所选
//   标签成员集合的条目并重新索引，不改动宿主的差分与渲染流程。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 宿主接口声明（互操作用，仅声明不含实现）

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

// 微信「标签」管理器（通讯录好友分组）
@interface ContactTagMgr : NSObject
- (NSArray *)getAllLabelName;                 // 所有标签名（真实名称）
- (NSArray *)getContactsForTagName:(NSString *)name; // 标签名 -> 成员(CContact)数组
@end

@interface CBaseContact : NSObject
- (NSString *)m_nsUsrName;
@end

// 朋友圈数据项
@interface WCDataItem : NSObject
- (NSString *)username;                        // 作者 username
@end

// 朋友圈数据门面：真正提供 count / getIndex 的类
@interface WCFacade : NSObject
- (unsigned long long)countOfTimelineDataItem;
- (id)getTimelineDataItemOfIndex:(unsigned long long)idx;
- (void)reloadTimelineDataItems;
@end

// 朋友圈主控制器
@interface WCTimeLineViewController : UIViewController
- (void)reloadTableView;
- (void)reloadDataWrap;
@end

// 第三方「微信插件管理」注册中心（可选依赖）
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
- (NSArray *)plugins;
@end

#pragma mark - 持久化键

static NSString *const kMTFEnabled       = @"MTFEnabled";          // 总开关
static NSString *const kMTFSelectedNames  = @"MTFSelectedTagNames"; // 选中的标签名数组

static NSString *MTFAuthorOfItem(id item) {
    if ([item respondsToSelector:@selector(username)]) {
        id v = [item username];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    }
    @try { id v = [item valueForKey:@"_username"]; if ([v isKindOfClass:[NSString class]]) return v; } @catch (__unused id e) {}
    return nil;
}

#pragma mark - 筛选引擎

@interface MTFManager : NSObject
@property (nonatomic, strong) NSSet<NSString *> *allowedUsernames;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, weak)   WCTimeLineViewController *activeMomentsVC;
+ (instancetype)shared;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)on;
- (BOOL)isActive;                              // 开 且 选了至少一个标签
- (NSArray<NSString *> *)allTagNames;
- (NSArray<NSString *> *)selectedNames;
- (void)setName:(NSString *)name selected:(BOOL)sel;
- (void)clearSelection;
- (BOOL)isUsernameAllowed:(NSString *)u;
- (void)refreshAndReload;
@end

@implementation MTFManager

+ (instancetype)shared { static MTFManager *s; static dispatch_once_t t; dispatch_once(&t,^{ s=[MTFManager new]; }); return s; }

- (ContactTagMgr *)tagMgr {
    Class c = objc_getClass("ContactTagMgr"), sc = objc_getClass("MMServiceCenter");
    if (!c || !sc) return nil;
    @try { return [[sc defaultCenter] getService:c]; } @catch (__unused id e) { return nil; }
}

- (BOOL)enabled { return [[NSUserDefaults standardUserDefaults] boolForKey:kMTFEnabled]; }
- (void)setEnabled:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kMTFEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSArray<NSString *> *)allTagNames {
    ContactTagMgr *mgr = [self tagMgr];
    if (!mgr) return @[];
    @try {
        NSArray *names = [mgr getAllLabelName];
        NSMutableArray *out = [NSMutableArray array];
        for (id n in names) if ([n isKindOfClass:[NSString class]] && [(NSString *)n length]) [out addObject:n];
        return out;
    } @catch (__unused id e) { return @[]; }
}

- (NSArray<NSString *> *)selectedNames {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kMTFSelectedNames];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}

- (void)setName:(NSString *)name selected:(BOOL)sel {
    NSMutableArray *a = [[self selectedNames] mutableCopy];
    [a removeObject:name];
    if (sel) [a addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kMTFSelectedNames];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)clearSelection {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTFSelectedNames];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isActive { return [self enabled] && [self selectedNames].count > 0; }

- (void)recomputeAllowed {
    if (![self isActive]) { self.allowedUsernames = nil; return; }
    ContactTagMgr *mgr = [self tagMgr];
    if (!mgr) { self.allowedUsernames = nil; return; }
    NSMutableSet *set = [NSMutableSet set];
    @try {
        for (NSString *name in [self selectedNames]) {
            NSArray *contacts = nil;
            @try { contacts = [mgr getContactsForTagName:name]; } @catch (__unused id e) {}
            for (id c in contacts) {
                NSString *u = nil;
                if ([c isKindOfClass:[NSString class]]) u = c;
                else if ([c respondsToSelector:@selector(m_nsUsrName)]) u = [c m_nsUsrName];
                else if ([c respondsToSelector:@selector(getUsername)]) u = ((id(*)(id,SEL))objc_msgSend)(c,@selector(getUsername));
                if ([u isKindOfClass:[NSString class]] && u.length) [set addObject:u];
            }
        }
    } @catch (__unused id e) {}
    self.allowedUsernames = set;
}

- (BOOL)isUsernameAllowed:(NSString *)u {
    if (![self isActive]) return YES;
    if (!self.allowedUsernames) return YES;
    if (![u isKindOfClass:[NSString class]] || !u.length) return NO; // 广告/无作者：筛选时隐藏
    return [self.allowedUsernames containsObject:u];
}

- (void)refreshAndReload {
    self.generation++;
    [self recomputeAllowed];
    WCTimeLineViewController *vc = self.activeMomentsVC;
    if (!vc) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { if ([vc respondsToSelector:@selector(reloadDataWrap)]) [vc reloadDataWrap]; } @catch (__unused id e) {}
        @try { if ([vc respondsToSelector:@selector(reloadTableView)]) [vc reloadTableView]; } @catch (__unused id e) {}
    });
}

@end

#pragma mark - 设置 / 标签选择页（插件管理入口 与 朋友圈入口 共用）

@interface MTFSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSString *> *tags;
@property (nonatomic, assign) BOOL presentedModally;
@end

@implementation MTFSettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"朋友圈标签筛选";
    self.tags = [[MTFManager shared] allTagNames];
    if (self.presentedModally)
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.tags=[[MTFManager shared] allTagNames]; [self.tableView reloadData]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 1 : (NSInteger)self.tags.count;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"总开关" : @"按好友标签筛选（可多选）";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"开启后，朋友圈页右上角出现筛选按钮；关闭则不显示入口，也不过滤。";
    if (s == 1 && self.tags.count == 0) return @"未读取到好友标签。请先在微信「通讯录 → 标签」中创建标签并添加好友。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    MTFManager *m = [MTFManager shared];
    if (ip.section == 0) {
        UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"sw"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sw"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"启用朋友圈筛选";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [m enabled];
        [sw addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"tag"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tag"];
    NSString *name = self.tags[ip.row];
    cell.textLabel.text = name;
    BOOL on = [[m selectedNames] containsObject:name];
    cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)toggleEnabled:(UISwitch *)sw {
    [[MTFManager shared] setEnabled:sw.on];
    [[MTFManager shared] refreshAndReload];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) return;
    MTFManager *m = [MTFManager shared];
    NSString *name = self.tags[ip.row];
    BOOL on = [[m selectedNames] containsObject:name];
    [m setName:name selected:!on];
    [m refreshAndReload];
    [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end

#pragma mark - Hook：WCFacade 过滤投影

static NSArray<NSNumber *> *gMap = nil;
static NSUInteger gMapGen = NSUIntegerMax;
static unsigned long long gMapOrigCount = ULLONG_MAX;
static BOOL gBuilding = NO;

static void MTFRebuildMapIfNeeded(WCFacade *self, unsigned long long origCount) {
    MTFManager *m = [MTFManager shared];
    if (gMap && gMapGen == m.generation && gMapOrigCount == origCount) return;
    NSMutableArray *map = [NSMutableArray arrayWithCapacity:(NSUInteger)origCount];
    gBuilding = YES;
    for (unsigned long long i = 0; i < origCount; i++) {
        id item = nil;
        @try { item = [self getTimelineDataItemOfIndex:i]; } @catch (__unused id e) {}
        if ([m isUsernameAllowed:MTFAuthorOfItem(item)]) [map addObject:@(i)];
    }
    gBuilding = NO;
    gMap = map; gMapGen = m.generation; gMapOrigCount = origCount;
}

%hook WCFacade

- (unsigned long long)countOfTimelineDataItem {
    unsigned long long orig = %orig;
    MTFManager *m = [MTFManager shared];
    if (![m isActive]) return orig;
    MTFRebuildMapIfNeeded(self, orig);
    return (unsigned long long)gMap.count;
}

- (id)getTimelineDataItemOfIndex:(unsigned long long)idx {
    MTFManager *m = [MTFManager shared];
    if (gBuilding || ![m isActive] || !gMap) return %orig;
    if (idx < gMap.count) return %orig([gMap[(NSUInteger)idx] unsignedLongLongValue]);
    return %orig;
}

%end

#pragma mark - Hook：朋友圈页悬浮筛选入口（仅启用时显示）

%hook WCTimeLineViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [MTFManager shared].activeMomentsVC = self;

    UIView *host = self.view;
    UIButton *existing = (UIButton *)[host viewWithTag:0x4D544601];
    BOOL enabled = [[MTFManager shared] enabled];
    if (!enabled) { [existing removeFromSuperview]; return; }
    if (existing) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = 0x4D544601;
    CGFloat sz = 44.0;
    CGFloat top = host.safeAreaInsets.top > 0 ? host.safeAreaInsets.top : 64.0;
    btn.frame = CGRectMake(host.bounds.size.width - sz - 10, top + 6, sz, sz);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    btn.layer.cornerRadius = sz / 2.0;
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    if (@available(iOS 13.0, *)) {
        [btn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
    } else {
        [btn setTitle:@"筛选" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12];
    }
    [btn addTarget:self action:@selector(mtf_openFilter) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:btn];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if ([MTFManager shared].activeMomentsVC == self) [MTFManager shared].activeMomentsVC = nil;
}

%new
- (void)mtf_openFilter {
    MTFSettingsViewController *vc = [MTFSettingsViewController new];
    vc.presentedModally = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

%end

#pragma mark - 注册到「微信插件管理」

static void MTFRegisterIntoPluginsMgr(void) {
    Class cls = objc_getClass("WCPluginsMgr");
    if (!cls) return;
    @try {
        WCPluginsMgr *mgr = [cls sharedInstance];
        BOOL exists = NO;
        @try {
            for (id p in [mgr plugins]) {
                NSString *tt = nil;
                @try { tt = [p valueForKey:@"title"]; } @catch (__unused id e) {}
                if ([tt isEqualToString:@"朋友圈标签筛选"]) { exists = YES; break; }
            }
        } @catch (__unused id e) {}
        if (!exists)
            [mgr registerControllerWithTitle:@"朋友圈标签筛选" version:@"1.1.1" controller:@"MTFSettingsViewController"];
    } @catch (__unused id e) {}
}

%hook WCPluginsViewController
- (void)initData {
    MTFRegisterIntoPluginsMgr();
    %orig;
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ MTFRegisterIntoPluginsMgr(); });
}
