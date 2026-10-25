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

@interface CContact : CBaseContact
- (NSString *)getContactDisplayName;
@end

// 个人朋友圈页的官方路由（8.0.78 二进制已核对类型编码 v48@0:8@16@24I32I36@40）：
// navigateToUserPageViewController:(来源VC) contact:(CContact) scene:(uint) thumbnailCnt:(uint) source:(id)
@interface WCTimelineRouterHelper : NSObject
+ (void)navigateToUserPageViewController:(id)fromViewController contact:(id)contact scene:(unsigned int)scene thumbnailCnt:(unsigned int)thumbnailCnt source:(id)source;
@end

#pragma mark - 常量

// 版本号唯一来源（Tweak.xm 内三处共用；control 文件里的 Version 仍需手动同步）
static NSString *const kMTFVersion        = @"1.8.3";
static NSString *const kMTFChangelog = @"## v1.8.3（2026-10-25）\n\n- 更新日志改 markdown 渲染：之前是纯文本，`#`、反引号都原样显示；现在用 iOS 15 原生 markdown 解析渲染（标题加粗放大、列表圆点、代码等宽），老系统或解析失败时回退纯文本；页里不再放仓库的发版约定段落，只从版本小节开始\n\n## v1.8.2（2026-10-25）\n\n- 修排版错位：根因是末行分隔线用了 left=10000 的超大 inset 藏线，结果连带顶坏 cell 的布局边距，正文被推到屏外只剩尾字（总开关行、取消全选行、一级菜单两行全是末行，全中招）；现在末行不再特殊处理（分组表末行本来就不画分隔线），inset 另加 200 上限防御\n- 勾选改成 toggles：标签行的 ✓ 彻底拿掉，每行右侧换成苹果官方 UISwitch（与总开关同一组件），点行或拨开关都能切换\n\n## v1.8.1（2026-10-25）\n\n- 复刻系统 UI：v1.8.0 的 inset 分组在微信进程里丢了白卡（宿主改写了外观），现在每个 cell 自带白色圆角卡片背景（按首/末行切角），底部灰底、行间短分隔线与文字左对齐，不再依赖 tableView 自身的分组背景绘制\n- 版本行可点进：关于 → 版本点进去是更新日志页（内容与仓库 CHANGELOG.md 同步）\n- 长按门禁：朋友圈筛选总开关关闭后，朋友圈页长按头像不再进入功能；只有开启时才触发（要重新开启请走「我 → 插件」）\n- 勾选换成苹果官方图形：标签行的 ✓ 不再是字体字符，改成 SF Symbol checkmark（与系统 accessory 勾选同一个图形），蓝色随系统 tint\n\n## v1.8.0（2026-10-25）\n\n- 设置改成两级菜单：一级菜单是插件功能列表（目前只有「朋友圈筛选」一行，带蓝色标签图标和状态副文案「已开启 · 已选 N 个标签」/「已关闭」，点进去才是原来的开关 + 筛选列表二级菜单）；以后新增功能只在一级菜单加一行，结构不用再动\n- 全套换成 iOS 系统「设置」App 的原生样式：三级页面（功能列表、筛选页、成员名单）统一用 inset 分组列表（圆角卡片 + 灰底）、17pt 正文、灰色分组标题/脚注、蓝色操作行、标准 UISwitch 和系统勾选；图标是彩色圆角方块 + 白色 SF Symbol；不再引入任何第三方 UI 框架，UIKit 原生组件就是设置 App 自己用的那套\n- 入口统一进一级菜单：长按头像、我 → 插件都打开功能列表；顶部副标题是筛选快捷入口，直接落在筛选二级菜单，左上角返回可回一级菜单\n- 版本号改成代码内唯一常量，以后发版只改一处 + control 文件\n\n## v1.7.5（2026-10-25）\n\n- 底部浮标移到顶部：不再是底部黑色药丸，改成导航栏「朋友圈」标题正下方的 11pt 灰色副标题（🏷 标签 · 匹配 N 条），不遮挡内容；点副标题同样打开设置面板；离开信息流页（进好友个人页/设置页）时自动摘掉，返回时重新挂上（导航栏是各页面共用的，不摘会残留）\n- 多选后缀必显：之前多选时浮标只显前两个名字、「等共 N 个标签」时有时无；现在单标签显名字，多标签固定格式「首个 等共 N 个标签 · 匹配 N 条」，文案足够短、不会被截断，选 5 个就一定能看到「等共 5 个标签」\n\n## v1.7.4（2026-10-25）\n\n- 从好友个人页返回朋友圈不再自动转圈：删掉了信息流页每次出现都触发补拉的逻辑（之前只靠 3 秒冷却挡，返回稍久一点就重新转圈）；补拉只在筛选设置变更关闭时触发，下滑/上拉刷新走宿主自身分页\n- 多标签浮标显示优化：之前名字全拼在一起、浮标被撑出屏幕后两侧裁掉，看着只剩一个标签；现在名字总长 ≤18 字全显，更长时显前两个 +「等共 N 个标签」，且浮标宽度封顶屏宽-32、超了尾部截断\n\n## v1.7.3（2026-10-25）\n\n- 放慢补拉，看窗口能延多远：补拉检查间隔 1.5 秒 → 3 秒（降请求频率），单次上限 40 页 → 150 页，目标匹配 10 条 → 50 条；仍以服务器 noMore 为准，补拉时间会变长（约 32 页需 1 分半左右）\n- 其余与 v1.7.2 相同（无 CGI 拉取）\n\n## v1.7.2（2026-10-25）\n\n- 回滚：取消 CGI 拉取，代码还原到 v1.4.2（最后一个经真机验证不闪退的版本）。v1.6.0/v1.7.0/v1.7.1 的 CGI 拉取在真机上连续闪退，堆拷贝也没修好，不再继续猜\n- 恢复的功能：设置页全屏、成员名单（点成员跳原生个人页）、主页筛选投影 + 筛选状态浮标；筛选仍只覆盖主页时间线窗口内的动态，旧动态请点成员进个人页看\n\n## v1.7.1（2026-10-25）\n\n- 修勾选标签闪退：CGI 完成回调改显式堆拷贝再传给原生桥。v1.6.0/v1.7.0 两次闪退的共同点就是这条 CGI 调用，首要嫌疑是栈 block 以 id 形式经 objc_msgSend 传过去、桥接层若只存指针不拷贝，方法返回后回调即访野指针\n\n## v1.7.0（2026-10-25）\n\n- 去掉「聚合」按钮和聚合页：点聚合闪退，入口已删除\n- 改为筛选拉取：设置页勾选某个标签时，自动用 CGI 逐人拉取该组成员的个人页首页（串行、间隔 0.8 秒），按时间排成「筛选 · 标签名」一页；点行打开该成员个人页看全部。取消勾选时只关筛选、不拉取\n- 修 v1.6.0 的两个隐患：串行链改堆拷贝强自指（弱自指会让链在第一人后断掉）；联系人显示名解析全部回主线程（后台队列调联系人服务疑似闪退源之一）\n\n## v1.6.0（2026-10-24）\n\n- 聚合改为 CGI 直取：逐成员调用微信自己的首页接口（SnsDBManager 的 requestUserFirstPageAsync），串行、间隔 0.8 秒——相当于逐个打开个人页，不再只依赖本地缓存；结果与本地缓存合并、按时间倒序\n- 聚合页加逐人进度（已拉取 x/y 人 · 共 n 条），单个成员 8 秒无响应自动跳过，不卡住整页\n- 仍只拉每人首页；更早页的翻页后续再做\n\n## v1.5.0（2026-10-24）\n\n- 新增 B2 聚合动态：设置页每个标签行加「聚合 ›」按钮，把该标签成员在本地已缓存的朋友圈按时间倒序排成一页（每人最多 30 条、总共最多 500 条），点任意一条打开该成员的个人页\n- 聚合只读本地缓存、不发新网络请求：已打开过个人页的成员会显示更早内容；还没缓存的旧动态，点成员名打开个人页看一次后，下次聚合里就会出现\n\n## v1.4.2（2026-10-24）\n\n- 设置面板改为全屏呈现，修复半屏弹窗顶部遮挡、成员名单滚动时被标题栏压住的问题\n- 成员名单只显示名字，去掉 wxid 副标题\n- 信息流页新增筛选状态浮标：筛选生效时在页面底部显示已选标签与当前匹配条数，点浮标打开设置——筛选有没有生效一目了然\n\n## v1.4.1（2026-10-23）\n\n- 修复成员名单显示 wxid 的问题：标签成员先经通讯录管理器解析成完整好友对象再展示，名单显示备注名/昵称（与通讯录标签页一致）\n- 修复点成员闪退：跳转个人朋友圈前改用解析后的完整好友对象，解析不到时改为弹提示、不再闪退\n- 诊断信息增加成员元素类型探针，便于确认成员数据的真实结构\n\n## v1.4.0（2026-10-23）\n\n- 新增「成员直达」：设置页每个标签（含「未设置标签的朋友」）行右侧加「成员 ›」按钮，打开成员名单（按名字排序），点任意成员直接跳微信原生个人朋友圈页——主页时间线约 4 天窗口之外的旧动态也能看了\n- 附诊断结论：筛选与匹配逻辑经真机数据验证正确（成员交集与投影条数一致）；个别标签刷不出是其成员在主页时间线窗口内没有新动态，并非插件故障\n\n## v1.3.3（2026-10-23）\n\n- 排查版：设置页底部新增「生成诊断信息」，可一键生成并复制排查报告（标签成员数与样本、成员集合缓存对比、已扫描条数与时间跨度、作者交集），用于定位个别标签筛不出数据的问题\n- 修复潜在冷启动竞态：标签服务未就绪时算出的空集合不再被缓存钉死，下次判定会自动重算\n\n## v1.3.2（2026-10-23）\n\n- 修复筛选后经常刷不出数据：自动补拉改为「进度驱动」——以底层实际拉到的数据量判断每页是否生效，成功页上限提高到 40 页；请求被微信合并/未生效时自动重试，不再固定拉 10 次就停\n- 加载提示实时显示进度「已扫描 X 条 · 匹配 Y 条」，可区分是还在拉取还是确实没有数据\n- 说明：朋友圈主页时间线本身有深度上限（由微信服务端决定），太久远的动态只能在好友个人主页看到，超出部分插件无法拉取\n\n## v1.3.1（2026-10-23）\n\n- 修复「未设置标签的朋友」人数严重偏大：改为直接基于通讯录好友（isMyContact）减去已打标签的人，不再全量扫描误计入非好友\n- 筛选命中改回「标签→成员」集合（人数已验证准确）并惰性计算，修复部分标签筛不出 / 冷启动空白\n- 筛选后显示「正在加载」转圈，并自动受控补拉更多页，尽量把所选标签好友的近期朋友圈拉出来\n- 安装包文件名精简为 `momentsfil_<版本>_<布局>.deb`\n\n## v1.3.0（2026-10-23）\n\n- 标签匹配改为按联系人标签逐一匹配，修复部分标签筛不出、冷启动空白的问题\n- 标签列表内嵌显示人数\n- 导航栏改为不透明样式\n- 修复「未设置标签的朋友」人数统计\n- 补声明 getLabelsNameForContact: 接口\n\n## v1.1.1（2026-10-23）\n\n- 首个开源版本：朋友圈按好友标签分类筛选\n- 设置入口注册到「第三方插件管理」：启用开关 + 好友标签多选\n- 朋友圈页筛选入口（启用后显示）\n- 过滤采用非破坏性投影：只保留作者属于所选标签成员的条目，不改动宿主渲染流程";
static NSString *const kMTFEnabled        = @"MTFEnabled";
static NSString *const kMTFSelectedNames  = @"MTFSelectedTagNames";
static NSString *const kMTFIncludeUntagged= @"MTFIncludeUntagged";
static NSString *const kMTFNoTagKey       = @"__MTF_NOTAG__";

static const NSUInteger kMTFTargetMatch   = 50;   // 目标：补拉到至少这么多条匹配项（放宽，让窗口尽量往深处走）
static const NSUInteger kMTFMaxAutoPages   = 150; // 单次筛选最多「成功落地」的补拉页数（进度驱动计数；仍以服务器 noMore 为准）
static const NSUInteger kMTFMaxStallTicks  = 3;   // 一页发出后连续无增长的等待次数（间隔放慢后约 9 秒），超了视为请求被吞
static const NSUInteger kMTFMaxRetries     = 3;   // 请求被吞后最多重发次数
static const NSTimeInterval kMTFPageDelay  = 3.0; // 每次补拉检查间隔（放慢：降请求频率，看服务器是否多给几页）
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
// 诊断报告（实现见下方 hook 区，需要直接读 facade 原始条目）
static NSString *MTFBuildDiagnostics(void);
// 设置 UI 助手（定义在下方设置区；成员名单页在它之前，先前向声明）
static UIImage *MTFSettingsIcon(NSString *symbolName, UIColor *bg);
static void MTFApplySettingsNavAppearance(UINavigationBar *bar);
static void MTFStyleCardCell(UITableView *t, UITableViewCell *c, NSIndexPath *ip);
// 设置面板呈现（实现见下方长按入口区）
static void MTFPresentSettings(UIViewController *host);
// 副标题快捷入口：直接落在二级菜单（左上角返回可回一级菜单）
static void MTFPresentFilterSettings(UIViewController *host);

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
@property (nonatomic, weak)   UILabel *filterBadge;                 // 信息流上的筛选状态浮标
@property (nonatomic, copy)   NSString *filterBadgeText;            // 浮标当前文案（去重用）
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

// 不走缓存地现算一遍「选中标签成员并集」。标签服务未就绪（取不到数组）时返回 nil，
// 调用方不要把这种结果钉进缓存——那正是冷启动时把空集缓存死、筛选全空的竞态。
- (NSSet *)freshAllowedSet {
    ContactTagMgr *mgr=[self tagMgr];
    if(!mgr) return nil;
    NSMutableSet *allowed=[NSMutableSet set];
    BOOL ok=YES;
    for(NSString *name in [self selectedNames]){
        NSArray *cs=nil;
        @try{ cs=[mgr getContactsForTagName:name]; }@catch(__unused id e){ cs=nil; }
        if(![cs isKindOfClass:[NSArray class]]){ ok=NO; continue; }
        for(id c in cs){ NSString *u=MTFUsernameOfMember(c); if(u.length) [allowed addObject:u]; }
    }
    return ok ? allowed : nil;
}

// 惰性计算：选中标签成员并集 + 全部已打标签用户名。按代际缓存，修复冷启动空白。
- (void)ensureSets {
    if(self.dataGen==self.generation && self.allowedUsernames) return;
    NSSet *allowed=[self freshAllowedSet];
    if(!allowed) return;   // 服务未就绪：不写缓存，下次判定再算
    ContactTagMgr *mgr=[self tagMgr];
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

// 把标签成员元素解析成完整 CContact。真机实测（v1.4.0）：getContactsForTagName: 返回的
// 元素拿不到显示名、直接传给个人页路由还会闪退——元素多半只是用户名或轻量对象。
// 统一像通讯录标签页那样经 CContactMgr 按用户名取完整好友对象，名字与跳转才都正常。
- (id)resolveContact:(id)el {
    if(!el) return nil;
    Class cc=objc_getClass("CContact");
    if(cc && [el isKindOfClass:cc]) return el;
    NSString *u=MTFUsernameOfMember(el);
    if(!u.length) return nil;
    id c=nil;
    @try { c=[[self contactMgr] getContactByName:u]; } @catch(__unused id e){}
    if(cc && [c isKindOfClass:cc]) return c;
    return nil;
}

// 标签成员的联系人对象（成员列表展示/跳转用，顺序同系统返回）
- (NSArray *)contactsForTagName:(NSString *)name {
    ContactTagMgr *mgr=[self tagMgr]; if(!mgr||!name.length) return @[];
    NSArray *raw=nil;
    @try { raw=[mgr getContactsForTagName:name]; } @catch(__unused id e){}
    if(![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out=[NSMutableArray array];
    for(id el in raw){ id c=[self resolveContact:el]; [out addObject:c?:el]; }
    return out;
}

// 未标签好友的联系人对象：用户名集优先用异步已算好的 untaggedFriends，没有则同步现算
- (NSArray *)untaggedContacts {
    NSSet *names=self.untaggedFriends;
    if(!names){
        NSMutableSet *out=[NSMutableSet set];
        NSSet *tagged=[NSSet set];
        @try { NSDictionary *d=[[self tagMgr] getDicWithUserNameForAllTag];
            if([d isKindOfClass:[NSDictionary class]]) tagged=[NSSet setWithArray:[d allKeys]]; } @catch(__unused id e){}
        @try {
            CContactMgr *cm=[self contactMgr];
            NSArray *all=[cm getAllContactUserName];
            if([all isKindOfClass:[NSArray class]]) for(NSString *u in all){
                if(![u isKindOfClass:[NSString class]]||!u.length||[tagged containsObject:u]) continue;
                id c=nil; @try{ c=[cm getContactByName:u]; }@catch(__unused id e){}
                if(MTFIsFriend(c)) [out addObject:u];
            }
        } @catch(__unused id e){}
        names=out;
    }
    CContactMgr *cm=[self contactMgr];
    NSMutableArray *res=[NSMutableArray array];
    for(NSString *u in names){ id c=nil; @try{ c=[cm getContactByName:u]; }@catch(__unused id e){} if(c) [res addObject:c]; }
    return res;
}

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

// 筛选状态副标题：移到导航栏「朋友圈」标题正下方（11pt 灰字，不遮挡内容），
// 点它打开设置面板。单标签显名字；多标签必显「首个 等共 N 个标签」，
// 且文案足够短、不会被截断——多选状态一眼可见，不再出现“只显两个、后缀时有时无”。
- (void)refreshFilterBadge {
    if(![self isActive]){ [self removeFilterBadge]; return; }
    NSMutableArray *parts=[NSMutableArray arrayWithArray:[self selectedNames]];
    if([self includeUntagged]) [parts addObject:@"未标签"];
    NSString *label;
    if(parts.count<=1){
        NSString *n=parts.count?parts[0]:@"";
        if(n.length>16) n=[[n substringToIndex:16] stringByAppendingString:@"…"];
        label=n;
    } else {
        NSString *first=parts[0];
        if(first.length>12) first=[[first substringToIndex:12] stringByAppendingString:@"…"];
        label=[NSString stringWithFormat:@"%@ 等共 %lu 个标签", first, (unsigned long)parts.count];
    }
    NSString *txt=[NSString stringWithFormat:@"🏷 %@ · 匹配 %lu 条", label,(unsigned long)gMapCount()];
    UIViewController *vc=self.activeMomentsVC;
    UINavigationBar *bar=vc.navigationController.navigationBar;
    if([txt isEqualToString:self.filterBadgeText] && self.filterBadge.superview && self.filterBadge.superview==bar) return;
    self.filterBadgeText=txt;
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *vc2=self.activeMomentsVC;
        UINavigationBar *bar2=vc2.navigationController.navigationBar;
        if(!vc2 || !bar2 || ![self isActive]) return;
        UILabel *b=self.filterBadge;
        if(!b || b.superview!=bar2){
            [b removeFromSuperview];
            b=[[UILabel alloc] init];
            b.backgroundColor=[UIColor clearColor];
            b.textColor=[UIColor grayColor];
            b.font=[UIFont systemFontOfSize:11];
            b.textAlignment=NSTextAlignmentCenter;
            b.numberOfLines=1;
            b.lineBreakMode=NSLineBreakByTruncatingTail;
            b.userInteractionEnabled=YES;
            [b addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(filterBadgeTapped)]];
            [bar2 addSubview:b];
            self.filterBadge=b;
        }
        b.text=self.filterBadgeText;
        [b sizeToFit];
        CGRect f=b.frame; f.size.height=14;
        // 左右留出返回/相机按钮，超了尾部截断
        CGFloat maxW=bar2.bounds.size.width-120;
        if(f.size.width>maxW) f.size.width=maxW;
        f.origin.x=(bar2.bounds.size.width-f.size.width)/2;
        f.origin.y=bar2.bounds.size.height-14;
        b.frame=f;
        b.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin;
        [bar2 bringSubviewToFront:b];
    });
}
- (void)removeFilterBadge {
    self.filterBadgeText=nil;
    dispatch_async(dispatch_get_main_queue(),^{ [self.filterBadge removeFromSuperview]; self.filterBadge=nil; });
}
- (void)filterBadgeTapped {
    UIViewController *vc=self.activeMomentsVC;
    if(vc) MTFPresentFilterSettings(vc);
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

#pragma mark - 诊断页

@interface MTFDiagnosticsViewController : UIViewController
@property (nonatomic, copy) NSString *text;
@end

@implementation MTFDiagnosticsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"诊断信息";
    self.view.backgroundColor=[UIColor whiteColor];
    UITextView *tv=[[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    tv.editable=NO;
    tv.font=[UIFont systemFontOfSize:12];
    tv.text=self.text;
    [self.view addSubview:tv];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStyleDone target:self action:@selector(copyAll)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeDiag)];
}
- (void)copyAll { [UIPasteboard generalPasteboard].string=self.text; }
- (void)closeDiag { [self dismissViewControllerAnimated:YES completion:nil]; }

@end

#pragma mark - 成员名单（B1：点成员跳原生个人朋友圈页）

static NSString *MTFDisplayNameOfContact(id c){
    if(!c || [c isKindOfClass:[NSString class]]) return @"";
    @try { if([c respondsToSelector:@selector(getContactDisplayName)]){
        id n=[c getContactDisplayName];
        if([n isKindOfClass:[NSString class]] && [(NSString*)n length]) return n;
    } } @catch(__unused id e){}
    @try { SEL nickSel=@selector(m_nsNickName);
        if([c respondsToSelector:nickSel]){
            id n=((id(*)(id,SEL))objc_msgSend)(c, nickSel);
            if([n isKindOfClass:[NSString class]] && [(NSString*)n length]) return n;
        }
    } @catch(__unused id e){}
    @try { id n=[c valueForKey:@"m_nsNickName"];
        if([n isKindOfClass:[NSString class]] && [(NSString*)n length]) return n;
    } @catch(__unused id e){}
    NSString *u=MTFUsernameOfMember(c);
    return u.length?u:@"";
}

@interface MTFMemberListViewController : UITableViewController
@property (nonatomic, strong) NSArray *contacts;
@end

@implementation MTFMemberListViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    MTFApplySettingsNavAppearance(self.navigationController.navigationBar);
    if (@available(iOS 13.0, *)) self.tableView.backgroundColor=[UIColor systemGroupedBackgroundColor];
    // 按显示名排序，方便找人
    self.contacts=[self.contacts sortedArrayUsingComparator:^NSComparisonResult(id a, id b){
        return [MTFDisplayNameOfContact(a) localizedStandardCompare:MTFDisplayNameOfContact(b)];
    }];
}

- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    MTFStyleCardCell(t,c,ip);
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.contacts.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return self.contacts.count? @"点任意成员，打开他的个人朋友圈（全部历史动态）。" : @"没有读到成员。";
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    id contact=self.contacts[ip.row];
    NSString *disp=MTFDisplayNameOfContact(contact);
    c.textLabel.text=disp.length?disp:MTFUsernameOfMember(contact); // 只显示名字，不显示 wxid
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    // 跳转前务必拿到完整 CContact：轻量对象/用户名直接传给路由会闪退（v1.4.0 实测）
    id contact=[[MTFManager shared] resolveContact:self.contacts[ip.row]];
    if(!contact){
        UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"无法打开" message:@"没能读取到这位好友的完整资料。" preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    // 走宿主自己的路由打开个人朋友圈页；类/方法缺失时静默降级（不崩）
    Class router=objc_getClass("WCTimelineRouterHelper");
    SEL sel=@selector(navigateToUserPageViewController:contact:scene:thumbnailCnt:source:);
    if(router && [router respondsToSelector:sel]){
        @try {
            ((void(*)(id,SEL,id,id,unsigned int,unsigned int,id))objc_msgSend)
                ((id)router, sel, self, contact, 0, 0, nil);
        } @catch(__unused id e){}
    }
}

@end

#pragma mark - 设置 UI：系统「设置」App 同款组件

// iOS 设置式图标：彩色圆角方块 + 白色 SF Symbol（取不到符号时回退 🏷，不崩）
static UIImage *MTFSettingsIcon(NSString *symbolName, UIColor *bg){
    CGFloat size=29.0;
    UIGraphicsImageRendererFormat *fmt=[UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque=NO;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size,size) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,size,size) cornerRadius:7];
        [bg setFill]; [p fill];
        UIImage *sym=nil;
        if(@available(iOS 13.0,*)) sym=[UIImage systemImageNamed:symbolName];
        if(sym){
            UIImage *white=nil;
            if(@available(iOS 13.0,*)) white=[sym imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
            CGFloat s=20; [(white?:sym) drawInRect:CGRectMake((size-s)/2,(size-s)/2,s,s)];
        } else {
            NSString *e=@"🏷";
            NSDictionary *attrs=@{NSFontAttributeName:[UIFont systemFontOfSize:16]};
            CGSize ts=[e sizeWithAttributes:attrs];
            [e drawAtPoint:CGPointMake((size-ts.width)/2,(size-ts.height)/2) withAttributes:attrs];
        }
    }];
}

// 两级菜单共用：不透明导航栏，避免下滑时内容穿透到标题/「完成」下方造成文字重叠
static void MTFApplySettingsNavAppearance(UINavigationBar *bar){
    if(!bar) return;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *ap=[[UINavigationBarAppearance alloc] init];
        [ap configureWithOpaqueBackground];
        bar.standardAppearance=ap; bar.scrollEdgeAppearance=ap; bar.compactAppearance=ap;
    }
}

// 系统设置式卡片：不依赖 tableView 自身的分组背景绘制（宿主可能改写外观，
// v1.8.0 的白卡就是这么丢的）。每个 cell 自带白色圆角背景，按首/末行切角；
// 分隔线与文字左对齐（有图标的行再右挪图标宽 + 间距），末行藏掉分隔线。
// cell 已被 table 缩进时不再二次缩进（用 cell 宽与表宽判断），两种情况都对齐。
static void MTFStyleCardCell(UITableView *t, UITableViewCell *c, NSIndexPath *ip){
    NSInteger rows=[t numberOfRowsInSection:ip.section];
    BOOL first=(ip.row==0), last=(ip.row==rows-1);
    CGFloat tableW=t.bounds.size.width, cellW=c.bounds.size.width;
    CGFloat sideInset=(tableW-cellW) > 1 ? 0 : 16;
    c.backgroundColor=[UIColor clearColor];
    UIView *bg=[[UIView alloc] initWithFrame:c.bounds];
    bg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    bg.backgroundColor=[UIColor clearColor];
    UIView *card=[[UIView alloc] initWithFrame:CGRectMake(sideInset,0,cellW-2*sideInset,c.bounds.size.height)];
    card.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    if(@available(iOS 13.0,*)){
        card.backgroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc){
            return tc.userInterfaceStyle==UIUserInterfaceStyleDark ? [UIColor colorWithWhite:0.11 alpha:1] : [UIColor whiteColor];
        }];
    } else {
        card.backgroundColor=[UIColor whiteColor];
    }
    card.layer.cornerRadius=10;
    CACornerMask mask=0;
    if(first) mask|=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;
    if(last) mask|=kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner;
    card.layer.maskedCorners=mask;
    card.layer.masksToBounds=YES;
    [bg addSubview:card];
    c.backgroundView=bg;
    // 分隔线只设正常短 inset：千万别用超大 left inset 藏末行分隔线——
    // 实测 v1.8.1 翻车：left=10000 会连带顶坏 cell 的布局边距，正文被推到屏外只剩尾字
    // （总开关行、取消全选行、一级菜单两行全是末行，全中招；非末行正常）。
    // 分组表末行本来就不画分隔线，不需要藏。
    CGFloat sepLeft=sideInset+16;
    if(c.imageView.image) sepLeft+=29+12;
    if(sepLeft>200) sepLeft=200; // 防御：inset 永远不许大到影响布局
    c.separatorInset=UIEdgeInsetsMake(0,sepLeft,0,0);
}

// 更新日志页：内容与仓库 CHANGELOG.md 同步（kMTFChangelog，发版时重生成）
@interface MTFChangelogViewController : UIViewController
@end

@implementation MTFChangelogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"更新日志";
    self.view.backgroundColor=[UIColor systemBackgroundColor];
    UITextView *tv=[[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    tv.editable=NO;
    tv.backgroundColor=[UIColor clearColor];
    // iOS 15 原生 markdown 渲染：标题加粗放大、列表圆点、代码等宽；失败或老系统回退纯文本
    NSAttributedString *attr=nil;
    if(@available(iOS 15.0,*)){
        NSError *err=nil;
        attr=[[NSAttributedString alloc] initWithMarkdown:kMTFChangelog options:nil baseURL:nil error:&err];
        if(err) attr=nil;
    }
    if(attr) tv.attributedText=attr;
    else { tv.font=[UIFont systemFontOfSize:15]; tv.text=kMTFChangelog; }
    [self.view addSubview:tv];
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

#pragma mark - 一级菜单：插件功能列表（以后新增功能只在这里加一行）

// 二级菜单的接口提前声明（实现仍在下方）：一级菜单要 alloc 它并设属性，
// 只靠 @class 前向声明编译不过（+new、属性访问、传参都要完整接口）
@interface MTFSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *tags;
@property (nonatomic, assign) BOOL presentedModally;
@property (nonatomic, assign) BOOL changed;
@end

@interface MTFRootViewController : UITableViewController
@property (nonatomic, assign) BOOL presentedModally;
@end

@implementation MTFRootViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"朋友圈标签筛选";
    if(self.presentedModally)
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    MTFApplySettingsNavAppearance(self.navigationController.navigationBar);
    if (@available(iOS 13.0, *)) self.tableView.backgroundColor=[UIColor systemGroupedBackgroundColor];
}

- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    MTFStyleCardCell(t,c,ip);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData]; // 从二级菜单返回时刷新状态副文案
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

// section: 0 功能, 1 关于
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s==0 ? @"功能" : @"关于";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"以后新增的功能都会出现在这里。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if(ip.section==0){
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        c.imageView.image=MTFSettingsIcon(@"tag.fill", [UIColor systemBlueColor]);
        c.textLabel.text=@"朋友圈筛选";
        MTFManager *m=[MTFManager shared];
        NSUInteger total=[m selectedNames].count + ([m includeUntagged]?1:0);
        if(![m enabled]) c.detailTextLabel.text=@"已关闭";
        else if(total==0) c.detailTextLabel.text=@"已开启";
        else c.detailTextLabel.text=[NSString stringWithFormat:@"已开启 · 已选 %lu 个标签",(unsigned long)total];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.textLabel.text=@"版本";
    c.detailTextLabel.text=kMTFVersion;
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==1){ // 关于 → 版本：点进去看更新日志
        [self.navigationController pushViewController:[MTFChangelogViewController new] animated:YES];
        return;
    }
    if(ip.section!=0) return;
    MTFSettingsViewController *vc=[MTFSettingsViewController new];
    vc.presentedModally=NO; // 二级菜单：左上角返回一级菜单，不用「完成」
    [self.navigationController pushViewController:vc animated:YES];
}

@end

#pragma mark - 二级菜单：朋友圈筛选（开关 + 筛选列表）
// @interface 已在上方一级菜单前声明，这里只剩实现
@implementation MTFSettingsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"朋友圈筛选";
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=56.0;
    if(self.presentedModally)
        self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    MTFApplySettingsNavAppearance(self.navigationController.navigationBar);
    if (@available(iOS 13.0, *)) self.tableView.backgroundColor=[UIColor systemGroupedBackgroundColor];
}

- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    MTFStyleCardCell(t,c,ip);
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

// section: 0 开关, 1 批量操作, 2 列表, 3 排查
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if(s==0) return 1;
    if(s==1) return 2;
    if(s==3) return 1;
    return 1 + (NSInteger)self.tags.count; // 首行=未设置标签
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if(s==0) return @"总开关";
    if(s==1) return @"批量操作";
    if(s==3) return @"排查";
    return @"按好友标签筛选（可多选）";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"开启后方可在信息流页按标签过滤；长按信息流页「我的头像」可随时打开本面板。";
    if(s==2){
        if(self.tags.count==0) return @"未读取到好友标签。请先在「通讯录 → 标签」中创建标签并添加好友。";
        return @"拨动标签行右侧的开关选择筛选（点行同样切换）；点「成员」打开成员名单，点成员跳到他的个人朋友圈——主页时间线窗口之外的旧动态从那里看。";
    }
    return nil;
}

// 行右侧配件：苹果官方 toggles（UISwitch，与总开关同一组件）+ 「成员 ›」按钮。
// 勾选不再用 ✓（字体字符或 SF 图形都不符合用户要的 toggles 样式）。
// 布局：成员 62 + 间隙 8 + 开关 51 = 121 宽；点行同样切换（didSelectRow），点开关直接切换，
// 两路都不重复触发（点开关不会触发行选中，开关动作按绝对状态写，不取反）。
- (UIView *)accessoryForRow:(NSInteger)row selected:(BOOL)on {
    UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,121,31)];
    UIButton *btn=[UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame=CGRectMake(0,0,62,31);
    btn.titleLabel.font=[UIFont systemFontOfSize:17]; // 与正文同字号，整表统一
    [btn setTitle:@"成员 ›" forState:UIControlStateNormal];
    btn.tag=row;
    [btn addTarget:self action:@selector(openMembers:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:btn];
    UISwitch *sw=[[UISwitch alloc] initWithFrame:CGRectMake(70,0,51,31)];
    sw.on=on;
    sw.tag=row;
    [sw addTarget:self action:@selector(toggleTag:) forControlEvents:UIControlEventValueChanged];
    [box addSubview:sw];
    return box;
}

- (void)toggleTag:(UISwitch *)sw {
    MTFManager *m=[MTFManager shared];
    NSInteger row=sw.tag;
    if(row==0){ [m setIncludeUntagged:sw.on]; }
    else {
        if(row-1>=(NSInteger)self.tags.count) return;
        NSString *name=self.tags[row-1][@"name"];
        [m setName:name selected:sw.on];
    }
    self.changed=YES; [m applyFilterChanged];
    // 不整表刷新：开关本身已是目标状态，刷新只会让它闪一下
}

- (void)openMembers:(UIButton *)btn {
    NSInteger row=btn.tag;
    MTFManager *m=[MTFManager shared];
    MTFMemberListViewController *vc=[MTFMemberListViewController new];
    if(row==0){
        vc.title=@"未设置标签的朋友";
        vc.contacts=[m untaggedContacts];
    } else {
        if(row-1>=(NSInteger)self.tags.count) return;
        NSString *name=self.tags[row-1][@"name"];
        vc.title=name;
        vc.contacts=[m contactsForTagName:name];
    }
    if(self.navigationController) [self.navigationController pushViewController:vc animated:YES];
    else [self presentViewController:[[UINavigationController alloc] initWithRootViewController:vc] animated:YES completion:nil];
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
    if(ip.section==3){
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.textLabel.font=[UIFont systemFontOfSize:17];
        c.textLabel.textColor=self.view.tintColor?:[UIColor systemBlueColor];
        c.textLabel.text=@"生成诊断信息";
        return c;
    }
    // 每次新建，避免复用导致的文字错位；人数紧贴名字后、灰色括号，如「摄影师 (71)」
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if(ip.row==0){ // 未设置标签的朋友
        c.textLabel.attributedText=MTFNameCount(@"未设置标签的朋友",[m untaggedCount]);
        c.accessoryView=[self accessoryForRow:0 selected:[m includeUntagged]];
        return c;
    }
    NSDictionary *tag=self.tags[ip.row-1];
    NSString *name=tag[@"name"];
    c.textLabel.attributedText=MTFNameCount(name,[m memberCountForTag:tag]);
    BOOL on=[[m selectedNames] containsObject:name];
    c.accessoryView=[self accessoryForRow:ip.row selected:on];
    return c;
}

- (void)showDiagnostics {
    MTFDiagnosticsViewController *vc=[MTFDiagnosticsViewController new];
    vc.text=MTFBuildDiagnostics();
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
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
    if(ip.section==3){ [self showDiagnostics]; return; }
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

// 诊断报告：对比「缓存的成员集合 vs 现算的成员集合」、统计已扫描条目的作者与
// 时间跨度、算成员与作者的交集——一次分清是集合被毒化、作者格式对不上、
// 还是这些人的帖子根本不在主页时间线流里。
static NSString *MTFBuildDiagnostics(void){
    MTFManager *m=[MTFManager shared];
    NSMutableString *r=[NSMutableString string];
    [r appendFormat:@"MomentsTagFilter 诊断 (v%@)\n", kMTFVersion];
    [r appendFormat:@"开关: %@  已选标签: %@  含未标签: %@\n",
        [m enabled]?@"开":@"关",
        [m selectedNames].count?[[m selectedNames] componentsJoinedByString:@", "]:@"(无)",
        [m includeUntagged]?@"是":@"否"];
    [m ensureSets];
    NSSet *fresh=[m freshAllowedSet];
    [r appendFormat:@"成员集合: 缓存 %lu 人 / 现算 %@ 人  已打标签总集 %lu 人\n",
        (unsigned long)(m.allowedUsernames?m.allowedUsernames.count:0),
        fresh?[NSString stringWithFormat:@"%lu",(unsigned long)fresh.count]:@"取不到(服务未就绪)",
        (unsigned long)(m.taggedUnion?m.taggedUnion.count:0)];
    if(fresh && m.allowedUsernames && fresh.count!=m.allowedUsernames.count)
        [r appendString:@"⚠️ 缓存与现算不一致: 缓存是旧的或被冷启动毒化\n"];
    ContactTagMgr *tm=[m tagMgr];
    for(NSString *name in [m selectedNames]){
        NSMutableArray *sample=[NSMutableArray array]; NSInteger cnt=-1; id firstEl=nil;
        @try{ NSArray *cs=[tm getContactsForTagName:name];
            if([cs isKindOfClass:[NSArray class]]){ cnt=(NSInteger)cs.count; firstEl=cs.count?cs[0]:nil;
                for(id c in cs){ NSString *u=MTFUsernameOfMember(c); if(u.length){ [sample addObject:u]; if(sample.count>=3) break; } } }
        }@catch(__unused id e){}
        [r appendFormat:@"标签[%@]: 成员 %ld 人, 样本: %@\n", name,(long)cnt,
            sample.count?[sample componentsJoinedByString:@", "]:@"(无)"];
        if(firstEl){ // 元素类型探针：成员元素到底是什么类、解析后能否拿到名字
            id rc=[m resolveContact:firstEl];
            [r appendFormat:@"  元素类型: %@ → 解析为: %@ / 名字: %@\n",
                NSStringFromClass([firstEl class]),
                rc?NSStringFromClass([rc class]):@"(失败)",
                rc?MTFDisplayNameOfContact(rc):@"-"];
        }
    }
    WCFacade *f=m.facade;
    unsigned long long raw=m.rawCount;
    [r appendFormat:@"时间线原始条数: %llu  当前投影匹配: %lu 条\n",
        (unsigned long long)raw,(unsigned long)gMapCount()];
    if(f && raw){
        NSMutableSet *authors=[NSMutableSet set];
        unsigned int tMin=UINT_MAX, tMax=0;
        unsigned long long n=MIN(raw,4000ULL);
        gBuilding=YES;
        for(unsigned long long i=0;i<n;i++){
            id item=nil; @try{ item=[f getTimelineDataItemOfIndex:i]; }@catch(__unused id e){}
            if(!item) continue;
            NSString *u=MTFAuthorOfItem(item); if(u.length) [authors addObject:u];
            @try{ id tv=[item valueForKey:@"createtime"];
                if([tv isKindOfClass:[NSNumber class]]){ unsigned int t=[tv unsignedIntValue];
                    if(t){ if(t<tMin)tMin=t; if(t>tMax)tMax=t; } }
            }@catch(__unused id e){}
        }
        gBuilding=NO;
        NSDateFormatter *fmt=[[NSDateFormatter alloc] init]; fmt.dateFormat=@"MM-dd HH:mm";
        [r appendFormat:@"已扫描 %llu 条: 不同作者 %lu 人, 时间 %@ ~ %@\n", n,(unsigned long)authors.count,
            tMax?[fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:tMax]]:@"?",
            (tMin!=UINT_MAX)?[fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:tMin]]:@"?"];
        if(authors.count){
            NSArray *all=[authors allObjects];
            [r appendFormat:@"作者样本: %@\n",
                [[all subarrayWithRange:NSMakeRange(0,MIN(all.count,15))] componentsJoinedByString:@", "]];
        }
        if(fresh){
            NSMutableSet *inter=[fresh mutableCopy]; [inter intersectSet:authors];
            [r appendFormat:@"已选标签成员 ∩ 已扫描作者: %lu 人\n",(unsigned long)inter.count];
            if(inter.count){
                NSArray *ia=[inter allObjects];
                [r appendFormat:@"交集样本: %@\n",
                    [[ia subarrayWithRange:NSMakeRange(0,MIN(ia.count,5))] componentsJoinedByString:@", "]];
            }
        }
    } else {
        [r appendString:@"时间线: 还没进朋友圈页或暂无数据\n"];
    }
    [r appendFormat:@"补拉: 成功页 %lu  noMore %@\n",(unsigned long)m.fillPages, m.noMore?@"是":@"否"];
    return r;
}

%hook WCFacade

- (unsigned long long)countOfTimelineDataItem {
    unsigned long long orig=%orig;
    MTFManager *m=[MTFManager shared];
    m.facade=self;
    m.rawCount=orig;   // 回填底层总条数，供补拉的进度判定使用
    if(![m isActive]){ [m removeFilterBadge]; return orig; }
    MTFRebuildMapIfNeeded(self,orig);
    [m refreshFilterBadge];
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
    MTFRootViewController *vc = [MTFRootViewController new];
    vc.presentedModally = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:nil];
}

// 副标题是筛选状态的快捷入口：直接落在二级菜单，左上角返回可回一级菜单
static void MTFPresentFilterSettings(UIViewController *host) {
    MTFRootViewController *root = [MTFRootViewController new];
    root.presentedModally = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [host presentViewController:nav animated:YES completion:^{
        MTFSettingsViewController *vc=[MTFSettingsViewController new];
        vc.presentedModally=NO;
        [nav pushViewController:vc animated:NO];
    }];
}

#pragma mark - Hook：信息流页 —— 长按「我的头像」进入筛选

%hook WCTimeLineViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [MTFManager shared].activeMomentsVC=self;
    MTFAttachLongPress(self);
    [[MTFManager shared] refreshFilterBadge];
    // 不在这里自动补拉：从好友个人页返回时也会走到 viewDidAppear，
    // 每次都转圈正是用户投诉的点。补拉只在筛选设置变更关闭时触发（settings-closed），
    // 下滑/上拉刷新走宿主自身分页，投影经 hook 重建，不需要额外转圈。
}

- (void)viewDidLayoutSubviews {
    %orig;
    MTFAttachLongPress(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if([MTFManager shared].activeMomentsVC==self) [MTFManager shared].activeMomentsVC=nil;
    // 导航栏是各页面共用的，离开信息流页就摘掉副标题，免得残留在好友个人页/设置页上；
    // 返回时 viewDidAppear 会重新挂上
    [[MTFManager shared] removeFilterBadge];
}

%new
- (void)mtf_onAvatarLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    // 总开关关闭时不进功能：长按只是筛选功能的快捷入口，不是设置入口
    // （要重新开启请走「我 → 插件」）；只看总开关，不看有没有选标签，
    // 否则刚开启还没选标签时反而进不去
    if(![[MTFManager shared] enabled]) return;
    MTFPresentSettings(self);
}

%end

#pragma mark - 注册到「插件管理」

static void MTFRegisterIntoPluginsMgr(void){
    Class cls=objc_getClass("WCPluginsMgr"); if(!cls) return;
    @try {
        WCPluginsMgr *mgr=[cls sharedInstance]; BOOL exists=NO;
        @try { for(id p in [mgr plugins]){ NSString *tt=nil; @try{ tt=[p valueForKey:@"title"]; }@catch(__unused id e){} if([tt isEqualToString:@"朋友圈标签筛选"]){ exists=YES; break; } } } @catch(__unused id e){}
        if(!exists) [mgr registerControllerWithTitle:@"朋友圈标签筛选" version:kMTFVersion controller:@"MTFRootViewController"];
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
