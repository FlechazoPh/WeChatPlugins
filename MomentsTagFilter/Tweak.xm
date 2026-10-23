// MomentsTagFilter — 按好友标签分类筛选信息流
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
//   入口：长按信息流页面「我的头像」打开设置面板（启用开关 / 全选 / 取消全选 / 标签多选，
//        含「未设置标签的朋友」项、每个标签的成员人数，顺序与系统标签页一致）。
//   过滤：对数据门面的条目计数与取值做「过滤投影」，仅保留作者属于所选集合的条目并重新索引。
//   补拉：应用筛选后触发一次刷新，并以受控的数量/频次分页补拉较旧内容，避免数据缺失，
//        下滑时沿用宿主自身的分页继续加载，不改动宿主的差分与渲染流程。

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 宿主接口声明（互操作用，仅声明不含实现）

@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
- (id)getService:(Class)cls;
@end

@interface ContactTagMgr : NSObject
- (NSArray *)getAllLabelName;
- (NSArray *)getContactsForTagName:(NSString *)name;   // 标签名 -> 成员（可靠，人数正确）
- (NSDictionary *)getDicWithUserNameForAllTag;         // 已打标签的 用户名 -> 标签
@end

@interface CBaseContact : NSObject
- (NSString *)m_nsUsrName;
- (BOOL)isMyContact;        // 是否我的好友
- (BOOL)isBrandContact;     // 公众号/品牌
- (BOOL)isChatroom;         // 群
@end

@interface CContactMgr : NSObject
- (NSArray *)getAllContactUserName;
- (id)getContactByName:(NSString *)name;
@end

@interface WCDataItem : NSObject
- (NSString *)username;
@end

@interface WCFacade : NSObject
- (unsigned long long)countOfTimelineDataItem;
- (id)getTimelineDataItemOfIndex:(unsigned long long)idx;
- (void)updateTimelineHead;   // 刷新最新
- (void)updateTimelineTail;   // 加载更旧
@end

@interface WCTimeLineViewController : UIViewController
- (void)reloadTableView;
- (void)reloadDataWrap;
@end

@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
- (NSArray *)plugins;
@end

#pragma mark - 常量

static NSString *const kMTFEnabled        = @"MTFEnabled";
static NSString *const kMTFSelectedNames  = @"MTFSelectedTagNames";
static NSString *const kMTFIncludeUntagged= @"MTFIncludeUntagged";
static NSString *const kMTFNoTagKey       = @"__MTF_NOTAG__";

static const NSUInteger kMTFTargetMatch   = 10;   // 目标：补拉到至少这么多条匹配项
static const NSUInteger kMTFMaxAutoPages   = 40;  // 单次筛选最多「成功落地」的补拉页数（进度驱动计数）
static const NSUInteger kMTFMaxStallTicks  = 3;   // 一页发出后连续无增长的等待次数（约 4.5 秒），超了视为请求被吞
static const NSUInteger kMTFMaxRetries     = 3;   // 请求被吞后最多重发次数
static const NSTimeInterval kMTFPageDelay  = 1.5; // 每次补拉检查间隔（防封）
static const NSTimeInterval kMTFFillCooldown = 3.0;

static NSString *MTFAuthorOfItem(id item) {
    if ([item respondsToSelector:@selector(username)]) {
        id v = [item username];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    }
    @try { id v = [item valueForKey:@"_username"]; if ([v isKindOfClass:[NSString class]]) return v; } @catch (__unused id e) {}
    return nil;
}

// 当前匹配到的条数（实现见下方 hook 区）
static NSUInteger gMapCount(void);

#pragma mark - 筛选引擎

@interface MTFManager : NSObject
@property (nonatomic, strong) NSSet<NSString *> *allowedUsernames;  // 选中标签的成员并集（惰性算）
@property (nonatomic, strong) NSSet<NSString *> *taggedUnion;       // 所有已打标签的用户名
@property (nonatomic, assign) NSUInteger dataGen;                   // allowed/tagged 的计算代际
@property (nonatomic, strong) NSSet<NSString *> *untaggedFriends;   // 无标签的好友（异步算，仅用于显示人数）
@property (nonatomic, strong) NSMutableDictionary *countCache;      // 标签名 -> 人数
@property (nonatomic, strong) NSMutableDictionary *decisionCache;   // 用户名 -> 是否命中（按代际失效）
@property (nonatomic, assign) NSUInteger decisionGen;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) UIView *hud;                          // 加载转圈
@property (nonatomic, weak)   WCTimeLineViewController *activeMomentsVC;
@property (nonatomic, weak)   WCFacade *facade;
// 补拉状态（进度驱动：以底层条数是否真增长判断一页是否落地）
@property (nonatomic, assign) BOOL filling;
@property (nonatomic, assign) BOOL noMore;
@property (nonatomic, assign) NSUInteger fillPages;              // 已成功落地的页数
@property (nonatomic, assign) BOOL tailInFlight;                 // 已发出一页、等它落地
@property (nonatomic, assign) NSUInteger stallTicks;             // 在途页连续无增长的检查次数
@property (nonatomic, assign) NSUInteger retryCount;             // 请求被吞后的重发次数
@property (nonatomic, assign) unsigned long long rawCount;       // facade 底层总条数（hook 每次回填）
@property (nonatomic, assign) unsigned long long lastRawCount;   // 发页时的底层条数快照
@property (nonatomic, weak)   UILabel *hudLabel;                 // HUD 进度文字
@property (nonatomic, assign) NSTimeInterval lastFillAt;
+ (instancetype)shared;
@end

@implementation MTFManager

+ (instancetype)shared { static MTFManager *s; static dispatch_once_t t; dispatch_once(&t,^{ s=[MTFManager new]; s.countCache=[NSMutableDictionary dictionary]; }); return s; }

- (ContactTagMgr *)tagMgr {
    Class c=objc_getClass("ContactTagMgr"), sc=objc_getClass("MMServiceCenter");
    if(!c||!sc) return nil;
    @try { return [[sc defaultCenter] getService:c]; } @catch(__unused id e){ return nil; }
}
- (CContactMgr *)contactMgr {
    Class c=objc_getClass("CContactMgr"), sc=objc_getClass("MMServiceCenter");
    if(!c||!sc) return nil;
    @try { return [[sc defaultCenter] getService:c]; } @catch(__unused id e){ return nil; }
}

- (BOOL)enabled { return [[NSUserDefaults standardUserDefaults] boolForKey:kMTFEnabled]; }
- (void)setEnabled:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:kMTFEnabled]; [[NSUserDefaults standardUserDefaults] synchronize]; }
- (BOOL)includeUntagged { return [[NSUserDefaults standardUserDefaults] boolForKey:kMTFIncludeUntagged]; }
- (void)setIncludeUntagged:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:kMTFIncludeUntagged]; [[NSUserDefaults standardUserDefaults] synchronize]; }

// 有序标签列表：@[ @{@"id":..,@"name":..} ]，顺序与系统「通讯录标签」一致
- (NSArray<NSDictionary *> *)orderedTags {
    ContactTagMgr *mgr=[self tagMgr];
    NSMutableArray *out=[NSMutableArray array];
    if(!mgr) return out;
    @try {
        NSArray *order=nil; NSDictionary *idToName=nil;
        @try { order=[mgr valueForKey:@"_arrIdOrder"]; } @catch(__unused id e){}
        @try { idToName=[mgr valueForKey:@"_dicIdToName"]; } @catch(__unused id e){}
        if([order isKindOfClass:[NSArray class]] && [idToName isKindOfClass:[NSDictionary class]] && order.count){
            for(id tid in order){
                NSString *name=idToName[tid];
                if([name isKindOfClass:[NSString class]] && name.length)
                    [out addObject:@{@"id":tid,@"name":name}];
            }
        }
        if(!out.count){ // 兜底：无序名称
            NSArray *names=[mgr getAllLabelName];
            for(id n in names) if([n isKindOfClass:[NSString class]] && [(NSString*)n length]) [out addObject:@{@"id":n,@"name":n}];
        }
    } @catch(__unused id e){}
    return out;
}

- (NSInteger)memberCountForTag:(NSDictionary *)tag {
    NSString *name=tag[@"name"];
    if(![name isKindOfClass:[NSString class]] || !name.length) return -1;
    NSNumber *cached=self.countCache[name]; if(cached) return cached.integerValue;
    ContactTagMgr *mgr=[self tagMgr]; NSInteger cnt=-1;
    // 注意：getContactsForLabel: 需要「标签对象」(会对入参调 m_uiID)，传标签ID(NSNumber)会崩溃，
    // 这里一律用按名字查询，安全可靠。
    @try {
        NSArray *cs=[mgr getContactsForTagName:name];
        if([cs isKindOfClass:[NSArray class]]) cnt=(NSInteger)cs.count;
    } @catch(__unused id e){}
    if(cnt>=0) self.countCache[name]=@(cnt);
    return cnt;
}

- (NSArray<NSString *> *)selectedNames {
    NSArray *a=[[NSUserDefaults standardUserDefaults] arrayForKey:kMTFSelectedNames];
    return [a isKindOfClass:[NSArray class]]?a:@[];
}
- (void)setName:(NSString *)name selected:(BOOL)sel {
    NSMutableArray *a=[[self selectedNames] mutableCopy]; [a removeObject:name]; if(sel)[a addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kMTFSelectedNames];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)selectAll {
    NSMutableArray *a=[NSMutableArray array];
    for(NSDictionary *t in [self orderedTags]) [a addObject:t[@"name"]];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kMTFSelectedNames];
    [self setIncludeUntagged:YES];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)clearAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTFSelectedNames];
    [self setIncludeUntagged:NO];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isActive { return [self enabled] && ([self selectedNames].count>0 || [self includeUntagged]); }

static NSString *MTFUsernameOfMember(id c){
    if([c isKindOfClass:[NSString class]]) return c;
    if([c respondsToSelector:@selector(m_nsUsrName)]) { id u=[c m_nsUsrName]; if([u isKindOfClass:[NSString class]]) return u; }
    return nil;
}
static BOOL MTFIsFriend(id c){
    if(!c) return NO;
    @try {
        if([c respondsToSelector:@selector(isChatroom)] && [c isChatroom]) return NO;
        if([c respondsToSelector:@selector(isBrandContact)] && [c isBrandContact]) return NO;
        if([c respondsToSelector:@selector(isMyContact)]) return [c isMyContact];
    } @catch(__unused id e){}
    return NO;
}

// 惰性计算：选中标签成员并集 + 全部已打标签用户名。按代际缓存，修复冷启动空白。
- (void)ensureSets {
    if(self.dataGen==self.generation && self.allowedUsernames) return;
    ContactTagMgr *mgr=[self tagMgr];
    NSMutableSet *allowed=[NSMutableSet set];
    @try {
        for(NSString *name in [self selectedNames]){
            NSArray *cs=nil; @try{ cs=[mgr getContactsForTagName:name]; }@catch(__unused id e){}
            for(id c in cs){ NSString *u=MTFUsernameOfMember(c); if(u.length) [allowed addObject:u]; }
        }
    } @catch(__unused id e){}
    NSMutableSet *tagged=[NSMutableSet set];
    @try { NSDictionary *d=[mgr getDicWithUserNameForAllTag];
        if([d isKindOfClass:[NSDictionary class]]) for(id k in d) if([k isKindOfClass:[NSString class]]) [tagged addObject:k];
    } @catch(__unused id e){}
    self.allowedUsernames=allowed; self.taggedUnion=tagged;
    self.dataGen=self.generation;
    self.decisionCache=[NSMutableDictionary dictionary]; self.decisionGen=self.generation;
}

// 后台统计「未设置标签的朋友」人数：直接基于通讯录——好友(isMyContact) 且 不在已打标签集合
- (void)computeUntaggedAsyncThen:(void(^)(void))done {
    NSSet *tagged=nil;
    @try { NSDictionary *d=[[self tagMgr] getDicWithUserNameForAllTag];
        if([d isKindOfClass:[NSDictionary class]]) tagged=[NSSet setWithArray:[d allKeys]];
    } @catch(__unused id e){}
    NSSet *taggedSet=tagged?:[NSSet set];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
        NSMutableSet *out=[NSMutableSet set];
        @try {
            CContactMgr *cm=[self contactMgr];
            NSArray *all=nil; @try{ all=[cm getAllContactUserName]; }@catch(__unused id e){}
            if([all isKindOfClass:[NSArray class]]){
                for(NSString *u in all){
                    if(![u isKindOfClass:[NSString class]]||!u.length) continue;
                    if([taggedSet containsObject:u]) continue;      // 已打标签 → 跳过
                    id c=nil; @try{ c=[cm getContactByName:u]; }@catch(__unused id e){}
                    if(MTFIsFriend(c)) [out addObject:u];            // 是好友且无标签
                }
            }
        } @catch(__unused id e){}
        dispatch_async(dispatch_get_main_queue(),^{ self.untaggedFriends=out; if(done)done(); });
    });
}

- (NSInteger)untaggedCount { return self.untaggedFriends? (NSInteger)self.untaggedFriends.count : -1; }

// 命中判定：选中标签成员用「标签→成员」(人数已验证正确)；未设置标签用「好友且不在已打标签集合」
- (BOOL)isUsernameAllowed:(NSString *)u {
    if(![self isActive]) return YES;
    if(![u isKindOfClass:[NSString class]] || !u.length) return NO; // 广告/无作者：隐藏
    [self ensureSets];
    if([self.allowedUsernames containsObject:u]) return YES;
    if([self includeUntagged]){
        if([self.taggedUnion containsObject:u]) return NO;          // 有标签但未选中
        NSNumber *cached=self.decisionCache[u]; if(cached) return cached.boolValue;
        BOOL isFriend=NO;
        @try { id c=[[self contactMgr] getContactByName:u]; isFriend=MTFIsFriend(c); } @catch(__unused id e){}
        self.decisionCache[u]=@(isFriend);
        return isFriend;
    }
    return NO;
}

- (void)reloadMoments {
    WCTimeLineViewController *vc=self.activeMomentsVC; if(!vc) return;
    dispatch_async(dispatch_get_main_queue(),^{
        @try{ if([vc respondsToSelector:@selector(reloadDataWrap)]) [vc reloadDataWrap]; }@catch(__unused id e){}
        @try{ if([vc respondsToSelector:@selector(reloadTableView)]) [vc reloadTableView]; }@catch(__unused id e){}
    });
}

// 加载转圈（覆盖在朋友圈页中部）
- (void)showHUD {
    dispatch_async(dispatch_get_main_queue(),^{
        UIView *host=self.activeMomentsVC.view; if(!host) return;
        if(self.hud && self.hud.superview) return;
        UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,210,120)];
        box.center=CGPointMake(host.bounds.size.width/2, host.bounds.size.height/2);
        box.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
        box.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.72];
        box.layer.cornerRadius=14;
        UIActivityIndicatorView *ind=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        ind.center=CGPointMake(105,42); [ind startAnimating]; [box addSubview:ind];
        UILabel *lb=[[UILabel alloc] initWithFrame:CGRectMake(10,72,190,40)];
        lb.text=@"正在加载…"; lb.textColor=[UIColor whiteColor]; lb.font=[UIFont systemFontOfSize:13]; lb.textAlignment=NSTextAlignmentCenter;
        lb.numberOfLines=2;
        [box addSubview:lb];
        [host addSubview:box]; self.hud=box; self.hudLabel=lb;
    });
}
- (void)hideHUD {
    dispatch_async(dispatch_get_main_queue(),^{ [self.hud removeFromSuperview]; self.hud=nil; self.hudLabel=nil; });
}

// HUD 进度：让用户能区分「还在拉」与「确实没有」
- (void)updateHUD {
    UILabel *lb=self.hudLabel; if(!lb) return;
    NSString *txt=[NSString stringWithFormat:@"正在加载… 已扫描 %llu 条 · 匹配 %lu 条",
        (unsigned long long)self.rawCount,(unsigned long)gMapCount()];
    dispatch_async(dispatch_get_main_queue(),^{ lb.text=txt; });
}

- (void)applyFilterChanged {
    self.generation++;          // 使判定缓存与过滤投影失效
    [self reloadMoments];
}

// 受控补拉：刷新一次 + 分页补拉（有数量/频次上限，防封；靠宿主自身分页，去重由宿主保证）
- (void)startFillBecause:(NSString *)reason {
    if(![self isActive]) return;
    WCFacade *f=self.facade; if(!f) return;
    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    if(self.filling) return;
    if(now-self.lastFillAt < kMTFFillCooldown) return;
    self.lastFillAt=now; self.filling=YES; self.noMore=NO;
    self.fillPages=0; self.tailInFlight=NO; self.stallTicks=0; self.retryCount=0;
    self.lastRawCount=self.rawCount;
    [self showHUD];
    dispatch_async(dispatch_get_main_queue(),^{
        @try{ [f updateTimelineHead]; }@catch(__unused id e){}   // 刷新一次最新
        [self scheduleFillStep];
    });
}

- (void)scheduleFillStep {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(kMTFPageDelay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self fillStep];
    });
}

- (void)fillStep {
    if(![self isActive]){ self.filling=NO; [self hideHUD]; return; }
    WCFacade *f=self.facade; if(!f){ self.filling=NO; [self hideHUD]; return; }
    // 进度驱动：在途页让底层条数发生变化 = 真的落地了，按「成功页」计数
    if(self.tailInFlight && self.rawCount!=self.lastRawCount){
        self.tailInFlight=NO;
        self.fillPages++;
        self.stallTicks=0;
        self.lastRawCount=self.rawCount;
    }
    [self updateHUD];
    NSUInteger matched = gMapCount();         // 当前匹配条数
    if(matched>=kMTFTargetMatch || self.noMore || self.fillPages>=kMTFMaxAutoPages){
        self.filling=NO; [self hideHUD]; return;
    }
    if(self.tailInFlight){
        // 上一页还没落地：先等；等太久视为请求被宿主合并/吞掉，有限次重发
        self.stallTicks++;
        if(self.stallTicks<kMTFMaxStallTicks){ [self scheduleFillStep]; return; }
        if(self.retryCount>=kMTFMaxRetries){ self.filling=NO; [self hideHUD]; return; }
        self.retryCount++;
        self.stallTicks=0;
        self.tailInFlight=NO;   // 落到下面统一重发
    }
    if(!self.tailInFlight){
        self.tailInFlight=YES;
        self.lastRawCount=self.rawCount;
        @try{ [f updateTimelineTail]; }@catch(__unused id e){}  // 加载更旧一页
        [self reloadMoments];
    }
    [self scheduleFillStep];
}

@end

#pragma mark - 设置 / 标签选择页

// 「名字 (人数)」——人数紧贴名字、灰色括号，与系统通讯录标签页一致
static NSAttributedString *MTFNameCount(NSString *name, NSInteger cnt){
    UIFont *f=[UIFont systemFontOfSize:17];
    NSMutableAttributedString *s=[[NSMutableAttributedString alloc] initWithString:(name?:@"")
        attributes:@{NSFontAttributeName:f}];
    if(cnt>=0){
        NSAttributedString *suffix=[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%ld)",(long)cnt]
            attributes:@{NSFontAttributeName:f, NSForegroundColorAttributeName:[UIColor grayColor]}];
        [s appendAttributedString:suffix];
    }
    return s;
}

@interface MTFSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *tags;
@property (nonatomic, assign) BOOL presentedModally;
@property (nonatomic, assign) BOOL changed;
@end

@implementation MTFSettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"朋友圈标签筛选";
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=56.0;
    if(self.presentedModally)
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    // 不透明导航栏，避免下滑时内容穿透到标题/「完成」下方造成文字重叠
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *ap=[[UINavigationBarAppearance alloc] init];
        [ap configureWithOpaqueBackground];
        UINavigationBar *bar=self.navigationController.navigationBar;
        bar.standardAppearance=ap; bar.scrollEdgeAppearance=ap; bar.compactAppearance=ap;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tags=[[MTFManager shared] orderedTags];
    [self.tableView reloadData];
    // 异步算无标签好友人数，算好后刷新该行
    [[MTFManager shared] computeUntaggedAsyncThen:^{ [self.tableView reloadData]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 关闭面板时触发一次刷新 + 受控补拉
    if(self.changed) [[MTFManager shared] startFillBecause:@"settings-closed"];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

// section: 0 开关, 1 批量操作, 2 列表
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if(s==0) return 1;
    if(s==1) return 2;
    return 1 + (NSInteger)self.tags.count; // 首行=未设置标签
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if(s==0) return @"总开关";
    if(s==1) return @"批量操作";
    return @"按好友标签筛选（可多选）";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"开启后方可在信息流页按标签过滤；长按信息流页「我的头像」可随时打开本面板。";
    if(s==2 && self.tags.count==0) return @"未读取到好友标签。请先在「通讯录 → 标签」中创建标签并添加好友。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    MTFManager *m=[MTFManager shared];
    if(ip.section==0){
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.textLabel.text=@"启用朋友圈筛选"; c.textLabel.font=[UIFont systemFontOfSize:17];
        UISwitch *sw=[[UISwitch alloc] init]; sw.on=[m enabled];
        [sw addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView=sw; return c;
    }
    if(ip.section==1){
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.textLabel.font=[UIFont systemFontOfSize:17];
        c.textLabel.textColor=self.view.tintColor?:[UIColor systemBlueColor];
        c.textLabel.text = ip.row==0 ? @"全选" : @"取消全选";
        return c;
    }
    // 每次新建，避免复用导致的文字错位；人数紧贴名字后、灰色括号，如「摄影师 (71)」
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(ip.row==0){ // 未设置标签的朋友
        c.textLabel.attributedText=MTFNameCount(@"未设置标签的朋友",[m untaggedCount]);
        c.accessoryType=[m includeUntagged]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
        return c;
    }
    NSDictionary *tag=self.tags[ip.row-1];
    NSString *name=tag[@"name"];
    c.textLabel.attributedText=MTFNameCount(name,[m memberCountForTag:tag]);
    BOOL on=[[m selectedNames] containsObject:name];
    c.accessoryType=on?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return c;
}

- (void)toggleEnabled:(UISwitch *)sw {
    [[MTFManager shared] setEnabled:sw.on];
    self.changed=YES;
    [[MTFManager shared] applyFilterChanged];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    MTFManager *m=[MTFManager shared];
    if(ip.section==0) return;
    if(ip.section==1){
        if(ip.row==0) [m selectAll]; else [m clearAll];
        self.changed=YES; [m applyFilterChanged];
        [t reloadData]; return;
    }
    if(ip.row==0){ [m setIncludeUntagged:![m includeUntagged]]; }
    else { NSString *name=self.tags[ip.row-1][@"name"]; [m setName:name selected:![[m selectedNames] containsObject:name]]; }
    self.changed=YES; [m applyFilterChanged];
    [t reloadData]; // 整表刷新，杜绝单行复用错位
}

@end

#pragma mark - Hook：WCFacade 过滤投影 + 补拉入口

static NSArray<NSNumber *> *gMap = nil;
static NSUInteger gMapGen = NSUIntegerMax;
static unsigned long long gMapOrigCount = ULLONG_MAX;
static BOOL gBuilding = NO;

static NSUInteger gMapCount(void){ return gMap?gMap.count:0; }

static void MTFRebuildMapIfNeeded(WCFacade *self, unsigned long long origCount){
    MTFManager *m=[MTFManager shared];
    if(gMap && gMapGen==m.generation && gMapOrigCount==origCount) return;
    NSMutableArray *map=[NSMutableArray arrayWithCapacity:(NSUInteger)origCount];
    gBuilding=YES;
    for(unsigned long long i=0;i<origCount;i++){
        id item=nil; @try{ item=[self getTimelineDataItemOfIndex:i]; }@catch(__unused id e){}
        if([m isUsernameAllowed:MTFAuthorOfItem(item)]) [map addObject:@(i)];
    }
    gBuilding=NO;
    gMap=map; gMapGen=m.generation; gMapOrigCount=origCount;
}

%hook WCFacade

- (unsigned long long)countOfTimelineDataItem {
    unsigned long long orig=%orig;
    MTFManager *m=[MTFManager shared];
    m.facade=self;
    m.rawCount=orig;   // 回填底层总条数，供补拉的进度判定使用
    if(![m isActive]) return orig;
    MTFRebuildMapIfNeeded(self,orig);
    return (unsigned long long)gMap.count;
}

- (id)getTimelineDataItemOfIndex:(unsigned long long)idx {
    MTFManager *m=[MTFManager shared];
    if(gBuilding || ![m isActive] || !gMap) return %orig;
    if(idx<gMap.count) return %orig([gMap[(NSUInteger)idx] unsignedLongLongValue]);
    return %orig;
}

- (void)onNoMoreTimelineData {
    [MTFManager shared].noMore = YES;
    %orig;
}

%end

#pragma mark - 信息流头像长按：辅助函数（置于 Logos 指令块之外，避免解析问题）

static void MTFAttachLongPress(UIViewController *vc) {
    UIView *avatars[2] = {nil, nil};
    @try {
        id eh = [vc valueForKey:@"_expandableHeader"];
        if (eh && [eh respondsToSelector:@selector(headImageView)])
            avatars[0] = ((id(*)(id,SEL))objc_msgSend)(eh, @selector(headImageView));
    } @catch (__unused id e) {}
    @try {
        id hv = [vc valueForKey:@"_headerView"];
        if (hv && [hv respondsToSelector:@selector(m_headImageView)])
            avatars[1] = ((id(*)(id,SEL))objc_msgSend)(hv, @selector(m_headImageView));
    } @catch (__unused id e) {}
    for (int i = 0; i < 2; i++) {
        UIView *av = avatars[i];
        if (![av isKindOfClass:[UIView class]]) continue;
        if (objc_getAssociatedObject(av, "mtf_lp")) continue;
        av.userInteractionEnabled = YES;
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:vc action:@selector(mtf_onAvatarLongPress:)];
        lp.minimumPressDuration = 0.5;
        [av addGestureRecognizer:lp];
        objc_setAssociatedObject(av, "mtf_lp", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void MTFPresentSettings(UIViewController *host) {
    MTFSettingsViewController *vc = [MTFSettingsViewController new];
    vc.presentedModally = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Hook：信息流页 —— 长按「我的头像」进入筛选

%hook WCTimeLineViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [MTFManager shared].activeMomentsVC=self;
    MTFAttachLongPress(self);
    if([[MTFManager shared] isActive]) [[MTFManager shared] startFillBecause:@"moments-appear"];
}

- (void)viewDidLayoutSubviews {
    %orig;
    MTFAttachLongPress(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if([MTFManager shared].activeMomentsVC==self) [MTFManager shared].activeMomentsVC=nil;
}

%new
- (void)mtf_onAvatarLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    MTFPresentSettings(self);
}

%end

#pragma mark - 注册到「插件管理」

static void MTFRegisterIntoPluginsMgr(void){
    Class cls=objc_getClass("WCPluginsMgr"); if(!cls) return;
    @try {
        WCPluginsMgr *mgr=[cls sharedInstance]; BOOL exists=NO;
        @try { for(id p in [mgr plugins]){ NSString *tt=nil; @try{ tt=[p valueForKey:@"title"]; }@catch(__unused id e){} if([tt isEqualToString:@"朋友圈标签筛选"]){ exists=YES; break; } } } @catch(__unused id e){}
        if(!exists) [mgr registerControllerWithTitle:@"朋友圈标签筛选" version:@"1.3.2" controller:@"MTFSettingsViewController"];
    } @catch(__unused id e){}
}

%hook WCPluginsViewController
- (void)initData {
    MTFRegisterIntoPluginsMgr();
    %orig;
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ MTFRegisterIntoPluginsMgr(); });
}
