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
#include <dlfcn.h>

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
- (id)getContactByAlias:(NSString *)alias; // 按微信号直查（已确认存在）
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
static NSString *const kMTFVersion        = @"1.12.0";
static NSString *const kMTFChangelog = @"## v1.12.0\n\n- 公众号栏直跳升级：已关注时按微信号直查（getContactByAlias:，替代全量扫描，更准）；未关注时走网页版主页（profile_ext + MMWebViewController，带关注按钮），只差 __biz 一个值，填入即启用；两者都没有时仍提示 + 复制 ID。\n- 赞赏直跳说明：你的赞赏码是微信专属圆点码，通用解码器读不出来（已实测 5 种工具），直跳需要赞赏页链接（朋友扫码后从赞赏页复制）或一次性提取 payload，本版先不动打赏页，等链接到了再接。\n\n## v1.11.1（2026-10-25）\n\n- 筛选列表按官方选择标签页优化显示：勾选圆圈 28pt → 23pt（官方实测 22.7pt，勾与描边等比缩放、描边 1.5pt → 1pt）；右侧 … 按钮 28pt → 20pt（官方实测 19.7pt，圆点 2pt、间距 4pt 居中，按钮框仍 28pt 保证触控区）；副标题 14pt → 13pt；标签后数量 17pt → 13pt；分隔线起点跟随图标实际宽度，圆圈缩水后仍贴标题左缘；行高保持 64pt\n\n## v1.11.0（2026-10-25）\n\n- 更新日志页顶部加打赏栏：点进去是作者赞赏码页（赞赏码大图 + 神隐 + “谢谢老板”，可保存赞赏码到相册，微信扫一扫即可打赏、金额自填）；赞赏码图片随包安装，dylib 同目录定位，rootful/rootless 通用\n- 插件主页关于上面加公众号栏：秋先生的猫（AksCat），点进去推微信原生资料页；没关注时提示并可复制 ID\n\n## v1.10.1（2026-10-25）\n\n- 修分段控件超框：之前 frame 用 view 宽 -32，没扣 inset 分组 cell 自身的左右边距，「不看这些」右端比白卡多出 16pt；改约束布局，左右各贴 contentView 16pt，永远在卡内\n- 更新日志改成一版一卡：每版一节一张白圆角卡片（灰底 + 12pt 间距、无分隔线），标题左对齐、正文两端对齐，深色下文字自适应\n\n## v1.10.0（2026-10-25）\n\n- 筛选列表改成微信通讯录标签页样式：左侧圆圈勾选（选中微信绿实心 + 白勾、未选灰色空心，点行切换），标题「标签名 (人数)」，副标题前 8 个成员的备注/昵称（多于 8 人尾部加 …），右侧 … 按钮进成员页；行 toggles 拿掉（总开关仍是 UISwitch）\n- 成员页改用微信原生页：点 … 打开微信自己的标签成员页（搜索栏 + 右侧 A-Z 索引 + 头像 + 备注/昵称 + 底部添加/移出，标题「标签名 (人数)」）；原生页不可用时回退自带名单；「未设置标签的朋友」不是标签、没有原生页，沿用自带名单；从原生页返回后副标题与人数重算（增删成员后不显示旧数据）\n\n## v1.9.0（2026-10-25）\n\n- 不看某些标签：筛选页总开关下方加「只看这些 / 不看这些」切换；切到「不看这些」后，勾选的标签里的好友动态从信息流里去掉，其余人全部保留；「未设置标签的朋友」行在不看档同样可排除；两档勾选分开存，切档不丢另一档的选择；顶部副标题和一级菜单状态文案同步改成「🚫 不看 N 个标签 · 剩 M 条」；无勾选时不做任何过滤\n- 更新日志排版重写：v1.8.3 的 iOS 原生 markdown 解析在真机上整篇压成一段（换行、标题、列表全丢），改行级确定性渲染：版本标题 20pt 粗体 + 段间距、条目圆点 + 悬挂缩进、代码等宽、正文 16pt，换行显式拼进字符串，不再依赖解析器\n\n## v1.8.3（2026-10-25）\n\n- 更新日志改 markdown 渲染：之前是纯文本，`#`、反引号都原样显示；现在用 iOS 15 原生 markdown 解析渲染（标题加粗放大、列表圆点、代码等宽），老系统或解析失败时回退纯文本；页里不再放仓库的发版约定段落，只从版本小节开始\n\n## v1.8.2（2026-10-25）\n\n- 修排版错位：根因是末行分隔线用了 left=10000 的超大 inset 藏线，结果连带顶坏 cell 的布局边距，正文被推到屏外只剩尾字（总开关行、取消全选行、一级菜单两行全是末行，全中招）；现在末行不再特殊处理（分组表末行本来就不画分隔线），inset 另加 200 上限防御\n- 勾选改成 toggles：标签行的 ✓ 彻底拿掉，每行右侧换成苹果官方 UISwitch（与总开关同一组件），点行或拨开关都能切换\n\n## v1.8.1（2026-10-25）\n\n- 复刻系统 UI：v1.8.0 的 inset 分组在微信进程里丢了白卡（宿主改写了外观），现在每个 cell 自带白色圆角卡片背景（按首/末行切角），底部灰底、行间短分隔线与文字左对齐，不再依赖 tableView 自身的分组背景绘制\n- 版本行可点进：关于 → 版本点进去是更新日志页（内容与仓库 CHANGELOG.md 同步）\n- 长按门禁：朋友圈筛选总开关关闭后，朋友圈页长按头像不再进入功能；只有开启时才触发（要重新开启请走「我 → 插件」）\n- 勾选换成苹果官方图形：标签行的 ✓ 不再是字体字符，改成 SF Symbol checkmark（与系统 accessory 勾选同一个图形），蓝色随系统 tint\n\n## v1.8.0（2026-10-25）\n\n- 设置改成两级菜单：一级菜单是插件功能列表（目前只有「朋友圈筛选」一行，带蓝色标签图标和状态副文案「已开启 · 已选 N 个标签」/「已关闭」，点进去才是原来的开关 + 筛选列表二级菜单）；以后新增功能只在一级菜单加一行，结构不用再动\n- 全套换成 iOS 系统「设置」App 的原生样式：三级页面（功能列表、筛选页、成员名单）统一用 inset 分组列表（圆角卡片 + 灰底）、17pt 正文、灰色分组标题/脚注、蓝色操作行、标准 UISwitch 和系统勾选；图标是彩色圆角方块 + 白色 SF Symbol；不再引入任何第三方 UI 框架，UIKit 原生组件就是设置 App 自己用的那套\n- 入口统一进一级菜单：长按头像、我 → 插件都打开功能列表；顶部副标题是筛选快捷入口，直接落在筛选二级菜单，左上角返回可回一级菜单\n- 版本号改成代码内唯一常量，以后发版只改一处 + control 文件\n\n## v1.7.5（2026-10-25）\n\n- 底部浮标移到顶部：不再是底部黑色药丸，改成导航栏「朋友圈」标题正下方的 11pt 灰色副标题（🏷 标签 · 匹配 N 条），不遮挡内容；点副标题同样打开设置面板；离开信息流页（进好友个人页/设置页）时自动摘掉，返回时重新挂上（导航栏是各页面共用的，不摘会残留）\n- 多选后缀必显：之前多选时浮标只显前两个名字、「等共 N 个标签」时有时无；现在单标签显名字，多标签固定格式「首个 等共 N 个标签 · 匹配 N 条」，文案足够短、不会被截断，选 5 个就一定能看到「等共 5 个标签」\n\n## v1.7.4（2026-10-25）\n\n- 从好友个人页返回朋友圈不再自动转圈：删掉了信息流页每次出现都触发补拉的逻辑（之前只靠 3 秒冷却挡，返回稍久一点就重新转圈）；补拉只在筛选设置变更关闭时触发，下滑/上拉刷新走宿主自身分页\n- 多标签浮标显示优化：之前名字全拼在一起、浮标被撑出屏幕后两侧裁掉，看着只剩一个标签；现在名字总长 ≤18 字全显，更长时显前两个 +「等共 N 个标签」，且浮标宽度封顶屏宽-32、超了尾部截断\n\n## v1.7.3（2026-10-25）\n\n- 放慢补拉，看窗口能延多远：补拉检查间隔 1.5 秒 → 3 秒（降请求频率），单次上限 40 页 → 150 页，目标匹配 10 条 → 50 条；仍以服务器 noMore 为准，补拉时间会变长（约 32 页需 1 分半左右）\n- 其余与 v1.7.2 相同（无 CGI 拉取）\n\n## v1.7.2（2026-10-25）\n\n- 回滚：取消 CGI 拉取，代码还原到 v1.4.2（最后一个经真机验证不闪退的版本）。v1.6.0/v1.7.0/v1.7.1 的 CGI 拉取在真机上连续闪退，堆拷贝也没修好，不再继续猜\n- 恢复的功能：设置页全屏、成员名单（点成员跳原生个人页）、主页筛选投影 + 筛选状态浮标；筛选仍只覆盖主页时间线窗口内的动态，旧动态请点成员进个人页看\n\n## v1.7.1（2026-10-25）\n\n- 修勾选标签闪退：CGI 完成回调改显式堆拷贝再传给原生桥。v1.6.0/v1.7.0 两次闪退的共同点就是这条 CGI 调用，首要嫌疑是栈 block 以 id 形式经 objc_msgSend 传过去、桥接层若只存指针不拷贝，方法返回后回调即访野指针\n\n## v1.7.0（2026-10-25）\n\n- 去掉「聚合」按钮和聚合页：点聚合闪退，入口已删除\n- 改为筛选拉取：设置页勾选某个标签时，自动用 CGI 逐人拉取该组成员的个人页首页（串行、间隔 0.8 秒），按时间排成「筛选 · 标签名」一页；点行打开该成员个人页看全部。取消勾选时只关筛选、不拉取\n- 修 v1.6.0 的两个隐患：串行链改堆拷贝强自指（弱自指会让链在第一人后断掉）；联系人显示名解析全部回主线程（后台队列调联系人服务疑似闪退源之一）\n\n## v1.6.0（2026-10-24）\n\n- 聚合改为 CGI 直取：逐成员调用微信自己的首页接口（SnsDBManager 的 requestUserFirstPageAsync），串行、间隔 0.8 秒——相当于逐个打开个人页，不再只依赖本地缓存；结果与本地缓存合并、按时间倒序\n- 聚合页加逐人进度（已拉取 x/y 人 · 共 n 条），单个成员 8 秒无响应自动跳过，不卡住整页\n- 仍只拉每人首页；更早页的翻页后续再做\n\n## v1.5.0（2026-10-24）\n\n- 新增 B2 聚合动态：设置页每个标签行加「聚合 ›」按钮，把该标签成员在本地已缓存的朋友圈按时间倒序排成一页（每人最多 30 条、总共最多 500 条），点任意一条打开该成员的个人页\n- 聚合只读本地缓存、不发新网络请求：已打开过个人页的成员会显示更早内容；还没缓存的旧动态，点成员名打开个人页看一次后，下次聚合里就会出现\n\n## v1.4.2（2026-10-24）\n\n- 设置面板改为全屏呈现，修复半屏弹窗顶部遮挡、成员名单滚动时被标题栏压住的问题\n- 成员名单只显示名字，去掉 wxid 副标题\n- 信息流页新增筛选状态浮标：筛选生效时在页面底部显示已选标签与当前匹配条数，点浮标打开设置——筛选有没有生效一目了然\n\n## v1.4.1（2026-10-23）\n\n- 修复成员名单显示 wxid 的问题：标签成员先经通讯录管理器解析成完整好友对象再展示，名单显示备注名/昵称（与通讯录标签页一致）\n- 修复点成员闪退：跳转个人朋友圈前改用解析后的完整好友对象，解析不到时改为弹提示、不再闪退\n- 诊断信息增加成员元素类型探针，便于确认成员数据的真实结构\n\n## v1.4.0（2026-10-23）\n\n- 新增「成员直达」：设置页每个标签（含「未设置标签的朋友」）行右侧加「成员 ›」按钮，打开成员名单（按名字排序），点任意成员直接跳微信原生个人朋友圈页——主页时间线约 4 天窗口之外的旧动态也能看了\n- 附诊断结论：筛选与匹配逻辑经真机数据验证正确（成员交集与投影条数一致）；个别标签刷不出是其成员在主页时间线窗口内没有新动态，并非插件故障\n\n## v1.3.3（2026-10-23）\n\n- 排查版：设置页底部新增「生成诊断信息」，可一键生成并复制排查报告（标签成员数与样本、成员集合缓存对比、已扫描条数与时间跨度、作者交集），用于定位个别标签筛不出数据的问题\n- 修复潜在冷启动竞态：标签服务未就绪时算出的空集合不再被缓存钉死，下次判定会自动重算\n\n## v1.3.2（2026-10-23）\n\n- 修复筛选后经常刷不出数据：自动补拉改为「进度驱动」——以底层实际拉到的数据量判断每页是否生效，成功页上限提高到 40 页；请求被微信合并/未生效时自动重试，不再固定拉 10 次就停\n- 加载提示实时显示进度「已扫描 X 条 · 匹配 Y 条」，可区分是还在拉取还是确实没有数据\n- 说明：朋友圈主页时间线本身有深度上限（由微信服务端决定），太久远的动态只能在好友个人主页看到，超出部分插件无法拉取\n\n## v1.3.1（2026-10-23）\n\n- 修复「未设置标签的朋友」人数严重偏大：改为直接基于通讯录好友（isMyContact）减去已打标签的人，不再全量扫描误计入非好友\n- 筛选命中改回「标签→成员」集合（人数已验证准确）并惰性计算，修复部分标签筛不出 / 冷启动空白\n- 筛选后显示「正在加载」转圈，并自动受控补拉更多页，尽量把所选标签好友的近期朋友圈拉出来\n- 安装包文件名精简为 `momentsfil_<版本>_<布局>.deb`\n\n## v1.3.0（2026-10-23）\n\n- 标签匹配改为按联系人标签逐一匹配，修复部分标签筛不出、冷启动空白的问题\n- 标签列表内嵌显示人数\n- 导航栏改为不透明样式\n- 修复「未设置标签的朋友」人数统计\n- 补声明 getLabelsNameForContact: 接口\n\n## v1.1.1（2026-10-23）\n\n- 首个开源版本：朋友圈按好友标签分类筛选\n- 设置入口注册到「第三方插件管理」：启用开关 + 好友标签多选\n- 朋友圈页筛选入口（启用后显示）\n- 过滤采用非破坏性投影：只保留作者属于所选标签成员的条目，不改动宿主渲染流程";
static NSString *const kMTFEnabled        = @"MTFEnabled";
static NSString *const kMTFSelectedNames  = @"MTFSelectedTagNames";
static NSString *const kMTFIncludeUntagged= @"MTFIncludeUntagged";
// 筛选方式：0=只看选中标签（原逻辑），1=不看选中标签（排除）。两档各自独立存选择，
// 切档不丢另一档的勾选；谓词取反只改判定，投影/补拉/浮标 machinery 全部复用。
static NSString *const kMTFFilterMode     = @"MTFFilterMode";
static NSString *const kMTFExcludedNames  = @"MTFExcludedTagNames";
static NSString *const kMTFExcludeUntagged= @"MTFExcludeUntagged";
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
@property (nonatomic, strong) NSSet<NSString *> *blockedUsernames;  // 排除标签的成员并集（不看模式，惰性算）
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

// 筛选方式与不看模式的选择（与只看模式分开存，切档不互毁）
- (NSInteger)filterMode { return [[NSUserDefaults standardUserDefaults] integerForKey:kMTFFilterMode]; }
- (void)setFilterMode:(NSInteger)mode { [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kMTFFilterMode]; [[NSUserDefaults standardUserDefaults] synchronize]; }
- (NSArray<NSString *> *)excludedNames {
    NSArray *a=[[NSUserDefaults standardUserDefaults] arrayForKey:kMTFExcludedNames];
    return [a isKindOfClass:[NSArray class]]?a:@[];
}
- (BOOL)excludeUntagged { return [[NSUserDefaults standardUserDefaults] boolForKey:kMTFExcludeUntagged]; }
- (void)setExcludeUntagged:(BOOL)on { [[NSUserDefaults standardUserDefaults] setBool:on forKey:kMTFExcludeUntagged]; [[NSUserDefaults standardUserDefaults] synchronize]; }
// 当前档位的「未标签」勾选 / 标签勾选 / 批量操作入口（UI 只调这些，不用分档写两套）
- (BOOL)untaggedSelected { return [self filterMode]==1 ? [self excludeUntagged] : [self includeUntagged]; }
- (void)setUntagged:(BOOL)on { if([self filterMode]==1) [self setExcludeUntagged:on]; else [self setIncludeUntagged:on]; }
- (BOOL)isTagSelected:(NSString *)name {
    if([self filterMode]==1) return [[self excludedNames] containsObject:name];
    return [[self selectedNames] containsObject:name];
}

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
    // 按当前档位写：只看档改 selectedNames，不看档改 excludedNames
    NSString *key = [self filterMode]==1 ? kMTFExcludedNames : kMTFSelectedNames;
    NSArray *cur = [self filterMode]==1 ? [self excludedNames] : [self selectedNames];
    NSMutableArray *a=[cur mutableCopy]; [a removeObject:name]; if(sel)[a addObject:name];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)selectAll {
    NSMutableArray *a=[NSMutableArray array];
    for(NSDictionary *t in [self orderedTags]) [a addObject:t[@"name"]];
    if([self filterMode]==1){
        [[NSUserDefaults standardUserDefaults] setObject:a forKey:kMTFExcludedNames];
        [self setExcludeUntagged:YES];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:a forKey:kMTFSelectedNames];
        [self setIncludeUntagged:YES];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)clearAll {
    if([self filterMode]==1){
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTFExcludedNames];
        [self setExcludeUntagged:NO];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTFSelectedNames];
        [self setIncludeUntagged:NO];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isActive {
    if(![self enabled]) return NO;
    if([self filterMode]==1) return [self excludedNames].count>0 || [self excludeUntagged];
    return [self selectedNames].count>0 || [self includeUntagged];
}

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

// 不走缓存地现算一遍「给定标签名列表的成员并集」。标签服务未就绪（取不到数组）时返回 nil，
// 调用方不要把这种结果钉进缓存——那正是冷启动时把空集缓存死、筛选全空的竞态。
- (NSSet *)freshSetForNames:(NSArray<NSString *> *)names {
    ContactTagMgr *mgr=[self tagMgr];
    if(!mgr) return nil;
    NSMutableSet *allowed=[NSMutableSet set];
    BOOL ok=YES;
    for(NSString *name in names){
        NSArray *cs=nil;
        @try{ cs=[mgr getContactsForTagName:name]; }@catch(__unused id e){ cs=nil; }
        if(![cs isKindOfClass:[NSArray class]]){ ok=NO; continue; }
        for(id c in cs){ NSString *u=MTFUsernameOfMember(c); if(u.length) [allowed addObject:u]; }
    }
    return ok ? allowed : nil;
}
- (NSSet *)freshAllowedSet { return [self freshSetForNames:[self selectedNames]]; }
- (NSSet *)freshBlockedSet { return [self freshSetForNames:[self excludedNames]]; }

// 惰性计算：当前档位的成员集合（只看档=选中并集，不看档=排除并集）+ 全部已打标签用户名。
// 按代际缓存，修复冷启动空白。切档会 bump 代际（applyFilterChanged），所以这里按档取数不会串。
- (void)ensureSets {
    NSSet *cur = [self filterMode]==1 ? self.blockedUsernames : self.allowedUsernames;
    if(self.dataGen==self.generation && cur) return;
    NSSet *set = [self filterMode]==1 ? [self freshBlockedSet] : [self freshAllowedSet];
    if(!set) return;   // 服务未就绪：不写缓存，下次判定再算
    ContactTagMgr *mgr=[self tagMgr];
    NSMutableSet *tagged=[NSMutableSet set];
    @try { NSDictionary *d=[mgr getDicWithUserNameForAllTag];
        if([d isKindOfClass:[NSDictionary class]]) for(id k in d) if([k isKindOfClass:[NSString class]]) [tagged addObject:k];
    } @catch(__unused id e){}
    if([self filterMode]==1) self.blockedUsernames=set; else self.allowedUsernames=set;
    self.taggedUnion=tagged;
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

// 命中判定：只看档=保留选中标签成员（+可选未标签好友）；不看档=去掉排除标签成员
// （+可选未标签好友），其余全部保留。同一投影 machinery，谓词取反而已。
// 不看档在集合未就绪（服务未起）时 fail-open：一律保留，绝不因数据没到就把所有人藏起来。
- (BOOL)isUsernameAllowed:(NSString *)u {
    if(![self isActive]) return YES;
    if(![u isKindOfClass:[NSString class]] || !u.length) return NO; // 广告/无作者：隐藏
    [self ensureSets];
    if([self filterMode]==1){
        if(self.dataGen!=self.generation) return YES;               // 集合没算出来：先全放行
        if([self.blockedUsernames containsObject:u]) return NO;     // 在排除名单里：去掉
        if([self excludeUntagged]){
            if([self.taggedUnion containsObject:u]) return YES;     // 有标签且未被排除：保留
            NSNumber *cached=self.decisionCache[u]; if(cached) return !cached.boolValue;
            BOOL isFriend=NO;
            @try { id c=[[self contactMgr] getContactByName:u]; isFriend=MTFIsFriend(c); } @catch(__unused id e){}
            self.decisionCache[u]=@(isFriend);
            return !isFriend;                                       // 无标签好友：去掉；非好友：保留
        }
        return YES;
    }
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
    BOOL exclude=[self filterMode]==1;
    NSMutableArray *parts=[NSMutableArray arrayWithArray:exclude?[self excludedNames]:[self selectedNames]];
    if([self untaggedSelected]) [parts addObject:@"未标签"];
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
    NSString *txt=exclude
        ? [NSString stringWithFormat:@"🚫 不看 %@ · 剩 %lu 条", label,(unsigned long)gMapCount()]
        : [NSString stringWithFormat:@"🏷 %@ · 匹配 %lu 条", label,(unsigned long)gMapCount()];
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

#pragma mark - DEBUG 分支专用：页面出现记录（勿合入 main）
// 记录每个微信原生页面出现时的类名 + 字符串/链接型 ivar（文章页 URL 里含 __biz、赞赏页参数都在这类 ivar 里）。
// 只存本机诊断页，不上传任何东西；装回正式版即消失。
static NSMutableArray<NSString *> *gMTFPageLog = nil;
static NSString *MTFDebugDescribe(id v, int depth){
    if(!v) return nil;
    @try {
        if([v isKindOfClass:[NSString class]]) return ([(NSString*)v length]>300)?[[(NSString*)v substringToIndex:300] stringByAppendingString:@"…"]:v;
        if([v isKindOfClass:[NSURL class]]) return [(NSURL*)v absoluteString];
        if(depth<=0) return [NSString stringWithFormat:@"<%@>", NSStringFromClass([v class])];
        if([v isKindOfClass:[NSDictionary class]]){
            NSMutableString *r=[NSMutableString stringWithString:@"{"];
            for(id k in [(NSDictionary*)v allKeys]){
                NSString *ds=MTFDebugDescribe([(NSDictionary*)v objectForKey:k], 0);
                if(ds) [r appendFormat:@"%@:%@, ", k, ds];
                if(r.length>1500) break;
            }
            [r appendString:@"}"];
            return r;
        }
        if([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSSet class]]){
            NSArray *arr=[v isKindOfClass:[NSArray class]]?v:[(NSSet*)v allObjects];
            NSMutableString *r=[NSMutableString stringWithFormat:@"<%@:%lu>[", NSStringFromClass([v class]), (unsigned long)arr.count];
            for(id e in arr){
                NSString *ds=MTFDebugDescribe(e, 0);
                if(ds) [r appendFormat:@"%@, ", ds];
                if(r.length>1500) break;
            }
            [r appendString:@"]"];
            return r;
        }
        NSString *cname=NSStringFromClass([v class]);
        // v3：只深挖微信自家类（WC/MM 开头）与 Foundation 容器/字符串；相机、会话等其他对象只记类名，避免再碰闪退源
        if(![cname hasPrefix:@"WC"] && ![cname hasPrefix:@"MM"]) return [NSString stringWithFormat:@"<%@>", cname];
        NSMutableString *r=[NSMutableString stringWithFormat:@"<%@>", cname];
        unsigned int n=0;
        Ivar *ivars=class_copyIvarList([v class], &n);
        for(unsigned int i=0;i<n;i++){
            const char *tn=ivar_getTypeEncoding(ivars[i]);
            if(!tn || tn[0]!='@') continue;
            const char *nm=ivar_getName(ivars[i]);
            if(!nm) continue;
            id iv=object_getIvar(v, ivars[i]);
            NSString *ds=nil;
            @try { ds=MTFDebugDescribe(iv, 0); } @catch(__unused id ex2){}
            if(ds) [r appendFormat:@" %s=%@", nm, ds];
            if(r.length>1500) break;
        }
        if(ivars) free(ivars);
        return r;
    } @catch(__unused id ex){ return [NSString stringWithFormat:@"<%@>", NSStringFromClass([v class])]; }
}
static void MTFDebugRecordPage(UIViewController *vc){
    @try {
        if(!gMTFPageLog) gMTFPageLog=[NSMutableArray array];
        NSString *cls=NSStringFromClass([vc class]);
        if([cls hasPrefix:@"UI"] || [cls hasPrefix:@"MTF"]) return;
        // v3：只深挖赞赏页，其他页面只记类名（扫码页不再碰 ivar，v2 的闪退即由此而来）
        if(![cls isEqualToString:@"WCPayQRCodeRewardPayerDetailViewController"]){
            [gMTFPageLog addObject:[NSString stringWithFormat:@"[%@] %@\n", [NSDate date], cls]];
            while(gMTFPageLog.count>40) [gMTFPageLog removeObjectAtIndex:0];
            return;
        }
        NSMutableString *e=[NSMutableString stringWithFormat:@"[%@] %@\n", [NSDate date], cls];
        for(Class c=[vc class]; c && c!=[UIViewController class]; c=class_getSuperclass(c)){
            unsigned int n=0;
            Ivar *ivars=class_copyIvarList(c, &n);
            for(unsigned int i=0;i<n;i++){
                const char *tn=ivar_getTypeEncoding(ivars[i]);
                if(!tn || tn[0]!='@') continue;
                const char *nm=ivar_getName(ivars[i]);
                if(!nm) continue;
                id v=object_getIvar(vc, ivars[i]);
                NSString *ds=nil;
                @try { ds=MTFDebugDescribe(v, 1); } @catch(__unused id ex2){}
                if(ds) [e appendFormat:@"  %s = %@\n", nm, ds];
                if(e.length>3000) break;
            }
            if(ivars) free(ivars);
            if(e.length>3000) break;
        }
        // v4：定向取赞赏 payload（WCPayQRCodeRewardControlData 的 _scanUrl 就是扫码解出的串）
        @try {
            id mdata=[vc valueForKey:@"m_data"];
            id qrdata=[mdata valueForKey:@"_qrcodeRewardData"];
            NSString *scanUrl=[qrdata valueForKey:@"scanUrl"];
            NSString *srcUrl=[qrdata valueForKey:@"sourceWebViewUrl"];
            id recv=[qrdata valueForKey:@"receiverContact"];
            NSString *recvUsr=[recv valueForKey:@"m_nsUsrName"];
            if(scanUrl.length) [e appendFormat:@"  SCANURL = %@\n", scanUrl];
            if(srcUrl.length) [e appendFormat:@"  SRCURL = %@\n", srcUrl];
            if(recvUsr.length) [e appendFormat:@"  RECEIVER = %@\n", recvUsr];
        } @catch(__unused id ex3){}
        [gMTFPageLog addObject:e];
        while(gMTFPageLog.count>40) [gMTFPageLog removeObjectAtIndex:0];
    } @catch(__unused id ex){}
}
static NSString *MTFDebugPageLogText(void){
    if(!gMTFPageLog.count) return @"暂无记录。直接扫一次赞赏码，然后回到这里查看（v3 只深挖赞赏页）。";
    return [@"页面记录 v4（找 WCPayQRCodeRewardPayerDetailViewController 那条里的 SCANURL）：\n\n" stringByAppendingString:[gMTFPageLog componentsJoinedByString:@"\n"]];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    MTFDebugRecordPage(self);
}
%end

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
    if(c.imageView.image) sepLeft+=c.imageView.image.size.width+12; // 跟随图标实际宽度，圆圈缩水后分隔线仍贴标题左缘
    if(sepLeft>200) sepLeft=200; // 防御：inset 永远不许大到影响布局
    c.separatorInset=UIEdgeInsetsMake(0,sepLeft,0,0);
}

// 更新日志页：内容与仓库 CHANGELOG.md 同步（kMTFChangelog，发版时重生成）。
// 排版（v1.10.1）：一版一卡——每节（## 标题起）一张白圆角卡片（MTFStyleCardCell 的卡，
// 灰底 + 12pt 间距），正文两端对齐；标题左对齐 20pt 粗体，条目圆点 + 悬挂缩进，代码等宽。
// 行级确定性渲染，不依赖 iOS 原生 markdown 解析（v1.8.3 在真机上整篇压成一段的教训）。
static NSArray<NSArray<NSString *> *> *MTFChangelogSections(NSString *md){
    NSMutableArray *sections=[NSMutableArray array];
    NSMutableArray *cur=nil;
    for(NSString *line in [md componentsSeparatedByString:@"\n"]){
        if([line hasPrefix:@"## "] || [line hasPrefix:@"# "]){
            cur=[NSMutableArray array]; [sections addObject:cur];
        }
        if(!cur){ cur=[NSMutableArray array]; [sections addObject:cur]; }
        [cur addObject:line];
    }
    return sections;
}
static NSAttributedString *MTFRenderChangelogSection(NSArray<NSString *> *lines){
    NSMutableAttributedString *out=[[NSMutableAttributedString alloc] init];
    UIFont *hFont=[UIFont boldSystemFontOfSize:20];
    UIFont *bFont=[UIFont systemFontOfSize:16];
    UIFont *mFont=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    UIColor *fg=[UIColor labelColor]; // 自适应深浅色，避免属性串在深色下发黑
    for(NSString *line in lines){
        BOOL isHead=[line hasPrefix:@"## "] || [line hasPrefix:@"# "];
        BOOL isBullet=[line hasPrefix:@"- "];
        NSString *body=line;
        if([line hasPrefix:@"## "]) body=[line substringFromIndex:3];
        else if([line hasPrefix:@"# "]) body=[line substringFromIndex:2];
        else if(isBullet) body=[line substringFromIndex:2];
        NSMutableAttributedString *la=[[NSMutableAttributedString alloc] init];
        if(isBullet) [la appendAttributedString:[[NSAttributedString alloc] initWithString:@"•  " attributes:@{NSFontAttributeName:bFont, NSForegroundColorAttributeName:fg}]];
        NSArray<NSString *> *parts=[body componentsSeparatedByString:@"`"]; // 奇数段是 `code`
        for(NSUInteger i=0;i<parts.count;i++){
            UIFont *f=isHead?hFont:((i%2==1)?mFont:bFont);
            [la appendAttributedString:[[NSAttributedString alloc] initWithString:parts[i] attributes:@{NSFontAttributeName:f, NSForegroundColorAttributeName:fg}]];
        }
        NSMutableParagraphStyle *ps=[[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        if(isHead){ ps.alignment=NSTextAlignmentLeft; ps.paragraphSpacing=6; }
        else if(isBullet){ ps.alignment=NSTextAlignmentJustified; ps.paragraphSpacing=4; ps.firstLineHeadIndent=0; ps.headIndent=16; }
        else { ps.alignment=NSTextAlignmentJustified; ps.paragraphSpacing=4; }
        if(la.length) [la addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0,la.length)];
        [out appendAttributedString:la];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    // 节与节之间是空行分隔，渲染后节尾会多出空行段落，裁掉免得卡片底部多出空白
    while(out.length && [[out.string substringFromIndex:out.length-1] isEqualToString:@"\n"])
        [out deleteCharactersInRange:NSMakeRange(out.length-1,1)];
    return out;
}

// 打赏页与公众号跳转（v1.11.0）。
// 赞赏码图片随包安装在 dylib 同目录（layout/.../DynamicLibraries/reward.jpg，
// rootful 与 rootless 的 dylib 都在该目录；sideload 注入时 dylib 也可能在应用包内，
// 故先用 dladdr 定位当前 dylib 所在目录，再试两条固定路径）。
static NSString *MTFRewardImagePath(void){
    Dl_info info;
    if(dladdr((void *)MTFStyleCardCell, &info) && info.dli_fname){
        NSString *dir=[[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        NSString *cand=[dir stringByAppendingPathComponent:@"reward.jpg"];
        if([[NSFileManager defaultManager] fileExistsAtPath:cand]) return cand;
    }
    NSArray *cands=@[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/reward.jpg",
        @"/Library/MobileSubstrate/DynamicLibraries/reward.jpg",
    ];
    for(NSString *cand in cands) if([[NSFileManager defaultManager] fileExistsAtPath:cand]) return cand;
    return nil;
}

@interface MTFRewardViewController : UIViewController
@property (nonatomic, strong) UIImage *qrImage;
@end

@implementation MTFRewardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"打赏";
    self.view.backgroundColor=[UIColor systemBackgroundColor];
    NSString *path=MTFRewardImagePath();
    if(path) self.qrImage=[UIImage imageWithContentsOfFile:path];
    CGFloat qw=MIN(320, self.view.bounds.size.width-64);
    if(qw<200) qw=200;
    UIStackView *stack=[[UIStackView alloc] init];
    stack.axis=UILayoutConstraintAxisVertical;
    stack.alignment=UIStackViewAlignmentCenter;
    stack.spacing=12;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    if(self.qrImage){
        UIImageView *iv=[[UIImageView alloc] initWithImage:self.qrImage];
        iv.contentMode=UIViewContentModeScaleAspectFit;
        [iv.widthAnchor constraintEqualToConstant:qw].active=YES;
        [iv.heightAnchor constraintEqualToConstant:qw].active=YES;
        [stack addArrangedSubview:iv];
    } else {
        UILabel *miss=[[UILabel alloc] init];
        miss.text=@"赞赏码图片未随插件安装，请更新到最新版";
        miss.font=[UIFont systemFontOfSize:15];
        miss.textColor=[UIColor secondaryLabelColor];
        miss.numberOfLines=0; miss.textAlignment=NSTextAlignmentCenter;
        [stack addArrangedSubview:miss];
    }
    UILabel *name=[[UILabel alloc] init];
    name.text=@"神隐"; name.font=[UIFont boldSystemFontOfSize:17];
    [stack addArrangedSubview:name];
    UILabel *msg=[[UILabel alloc] init];
    msg.text=@"\u201c谢谢老板\u201d"; msg.font=[UIFont systemFontOfSize:16];
    [stack addArrangedSubview:msg];
    UILabel *hint=[[UILabel alloc] init];
    hint.text=@"微信扫一扫即可打赏，金额自填";
    hint.font=[UIFont systemFontOfSize:14]; hint.textColor=[UIColor secondaryLabelColor];
    [stack addArrangedSubview:hint];
    if(self.qrImage){
        UIButton *save=[UIButton buttonWithType:UIButtonTypeSystem];
        [save setTitle:@"保存赞赏码" forState:UIControlStateNormal];
        save.titleLabel.font=[UIFont systemFontOfSize:16];
        [save addTarget:self action:@selector(saveReward) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:save];
    }
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];
}

- (void)saveReward {
    if(!self.qrImage) return;
    UIImageWriteToSavedPhotosAlbum(self.qrImage, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:(error?@"保存失败":@"已保存到相册") message:(error?@"请在设置中允许微信访问相册后重试":@"在微信扫一扫里从相册选取这张赞赏码即可打赏") preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

// 公众号主页：通讯录里按用户名 / 别名 / 昵称找账号，找到就推微信原生资料页
// ContactInfoViewController（init + setM_contact:，未声明接口故走显式 objc_msgSend）；
// 没关注就找不到，弹提示并可复制 ID。
// 公众号主页：已关注 → 按别名直查通讯录（getContactByAlias:，比全量扫描干净）推微信原生资料页；
// 未关注 → profile_ext 网页版主页（MMWebViewController，带关注按钮），需 __biz；
// 两者都没有 → 提示 + 复制 ID。
// __biz 获取：秋先生的猫任意一篇文章 → 右上角 … → 复制链接，链接里 __biz= 后面那串；或公众平台后台。
static NSString *const kMTFOfficialBiz = nil; // 填入 __biz 后，非关注者点公众号栏直接进主页
static void MTFOpenOfficialAccount(UIViewController *from){
    NSString *alias=@"AksCat";
    NSString *accName=@"秋先生的猫";
    id found=nil;
    @try {
        CContactMgr *cm=[[MTFManager shared] contactMgr];
        @try { found=[cm getContactByAlias:alias]; } @catch(__unused id e){}
        if(!found){ @try { found=[cm getContactByName:alias]; } @catch(__unused id e){} }
    } @catch(__unused id e){}
    if(found){
        @try {
            Class civc=objc_getClass("ContactInfoViewController");
            id vc=[[civc alloc] init];
            ((void (*)(id, SEL, id))objc_msgSend)(vc, @selector(setM_contact:), found);
            [from.navigationController pushViewController:vc animated:YES];
            return;
        } @catch(__unused id e){}
    }
    if(kMTFOfficialBiz.length){
        @try {
            NSString *urlStr=[NSString stringWithFormat:@"https://mp.weixin.qq.com/mp/profile_ext?action=home&__biz=%@", kMTFOfficialBiz];
            NSURL *url=[NSURL URLWithString:urlStr];
            Class wvc=objc_getClass("MMWebViewController");
            id vc=((id (*)(id, SEL, id, BOOL, id))objc_msgSend)([wvc alloc], @selector(initWithURL:presentModal:extraInfo:), url, NO, nil);
            [from.navigationController pushViewController:vc animated:YES];
            return;
        } @catch(__unused id e){}
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:accName message:@"通讯录里没找到该公众号，请在微信里搜索 AksCat 关注" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"复制 ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act){
        [UIPasteboard generalPasteboard].string=alias;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [from presentViewController:a animated:YES completion:nil];
}

@interface MTFChangelogViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSAttributedString *> *sections;
@end

@implementation MTFChangelogViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"更新日志";
    self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone; // 卡片之间不要分隔线，靠间距
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=120;
    self.tableView.contentInset=UIEdgeInsetsMake(0,0,12,0); // 末卡底部留距
    if(@available(iOS 13.0,*)) self.tableView.backgroundColor=[UIColor systemGroupedBackgroundColor];
    NSMutableArray *secs=[NSMutableArray array];
    for(NSArray *lines in MTFChangelogSections(kMTFChangelog)){
        NSAttributedString *a=MTFRenderChangelogSection(lines);
        if(a.length) [secs addObject:a];
    }
    self.sections=secs;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1 + (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s { return 12; } // 卡片间距
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s {
    UIView *v=[[UIView alloc] init]; v.backgroundColor=[UIColor clearColor]; return v;
}
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    MTFStyleCardCell(t,c,ip); // 一节一行 = 首末同行，四角全圆的白卡
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if(ip.section==0){ // 顶部打赏栏 → 作者赞赏码页
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        c.imageView.image=MTFSettingsIcon(@"heart.fill", [UIColor systemRedColor]);
        c.textLabel.text=@"打赏";
        c.detailTextLabel.text=@"谢谢老板";
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle=UITableViewCellSelectionStyleNone;
    UILabel *lab=[[UILabel alloc] init];
    lab.numberOfLines=0;
    lab.attributedText=self.sections[ip.section-1];
    lab.translatesAutoresizingMaskIntoConstraints=NO;
    [c.contentView addSubview:lab];
    [NSLayoutConstraint activateConstraints:@[
        [lab.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:16],
        [lab.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-16],
        [lab.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],
        [lab.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],
    ]];
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0) [self.navigationController pushViewController:[MTFRewardViewController new] animated:YES];
}

@end

#pragma mark - 设置 / 标签选择页

// 「名字 (人数)」——人数紧贴名字、灰色括号，与系统通讯录标签页一致
static NSAttributedString *MTFNameCount(NSString *name, NSInteger cnt){
    UIFont *f=[UIFont systemFontOfSize:17];
    NSMutableAttributedString *s=[[NSMutableAttributedString alloc] initWithString:(name?:@"")
        attributes:@{NSFontAttributeName:f}];
    if(cnt>=0){ // 数量比名字小两档：官方数量 13pt（名字 15pt），这里名字保持 17pt、数量取 13pt
        UIFont *cf=[UIFont systemFontOfSize:13];
        NSAttributedString *suffix=[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%ld)",(long)cnt]
            attributes:@{NSFontAttributeName:cf, NSForegroundColorAttributeName:[UIColor grayColor]}];
        [s appendAttributedString:suffix];
    }
    return s;
}

// 微信通讯录标签页样式的圆圈勾选（28pt）：选中=微信绿 #07C160 实心 + 白 ✓；未选=灰色空心
static UIImage *MTFCircleCheck(BOOL on){
    CGFloat d=23; // 官方实测 22.7pt（原 28pt 太大）
    UIGraphicsImageRendererFormat *fmt=[UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque=NO;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d,d) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        (void)ctx;
        CGRect rect=CGRectMake(1,1,d-2,d-2);
        if(on){
            [[UIColor colorWithRed:0x07/255.0 green:0xC1/255.0 blue:0x60/255.0 alpha:1] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:rect] fill];
            UIBezierPath *tick=[UIBezierPath bezierPath];
            tick.lineWidth=1.8; tick.lineCapStyle=kCGLineCapRound; tick.lineJoinStyle=kCGLineJoinRound;
            [tick moveToPoint:CGPointMake(6.2,11.9)];
            [tick addLineToPoint:CGPointMake(10.3,16.0)];
            [tick addLineToPoint:CGPointMake(17.3,7.8)];
            [[UIColor whiteColor] setStroke];
            [tick stroke];
        } else {
            [[UIColor colorWithWhite:0.78 alpha:1] setStroke];
            UIBezierPath *circle=[UIBezierPath bezierPathWithOvalInRect:rect];
            circle.lineWidth=1.0; // 官方描边约 1pt（原 1.5pt 显粗）
            [circle stroke];
        }
    }];
}
// 微信标签页右侧 … 按钮（28pt）：灰色圆圈描边 + 三个点
static UIImage *MTFDotsImage(void){
    CGFloat d=20; // 官方实测 19.7pt（原 28pt 太大）；按钮框仍 28pt，保证触控区
    UIGraphicsImageRendererFormat *fmt=[UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque=NO;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d,d) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        (void)ctx;
        CGRect rect=CGRectMake(1,1,d-2,d-2);
        [[UIColor colorWithWhite:0.78 alpha:1] setStroke];
        UIBezierPath *circle=[UIBezierPath bezierPathWithOvalInRect:rect];
        circle.lineWidth=1.0;
        [circle stroke];
        [[UIColor colorWithWhite:0.55 alpha:1] setFill];
        for(int i=0;i<3;i++)
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(5+i*4,9,2,2)] fill]; // 圆点 2pt、间距 4pt，居中
    }];
}

#pragma mark - 一级菜单：插件功能列表（以后新增功能只在这里加一行）

// 二级菜单的接口提前声明（实现仍在下方）：一级菜单要 alloc 它并设属性，
// 只靠 @class 前向声明编译不过（+new、属性访问、传参都要完整接口）
@interface MTFSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *tags;
@property (nonatomic, assign) BOOL presentedModally;
@property (nonatomic, assign) BOOL changed;
@property (nonatomic, strong) NSMutableDictionary *subtitleCache; // 行 -> 前 8 个成员名副标题（每进页面重算）
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

// section: 0 功能, 1 公众号, 2 关于
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s==0 ? @"功能" : (s==1 ? @"公众号" : @"关于");
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
        BOOL exclude=[m filterMode]==1;
        NSUInteger total=exclude
            ? ([m excludedNames].count + ([m excludeUntagged]?1:0))
            : ([m selectedNames].count + ([m includeUntagged]?1:0));
        if(![m enabled]) c.detailTextLabel.text=@"已关闭";
        else if(total==0) c.detailTextLabel.text=@"已开启";
        else if(exclude) c.detailTextLabel.text=[NSString stringWithFormat:@"已开启 · 不看 %lu 个标签",(unsigned long)total];
        else c.detailTextLabel.text=[NSString stringWithFormat:@"已开启 · 已选 %lu 个标签",(unsigned long)total];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if(ip.section==1){ // 公众号 → 微信原生资料页
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        c.imageView.image=MTFSettingsIcon(@"bubble.left.and.bubble.right.fill", [UIColor systemGreenColor]);
        c.textLabel.text=@"秋先生的猫";
        c.detailTextLabel.text=@"AksCat";
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
    if(ip.section==1){ // 公众号 → 微信原生资料页
        MTFOpenOfficialAccount(self);
        return;
    }
    if(ip.section==2){ // 关于 → 版本：点进去看更新日志
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
    // 原生成员页可能增删过成员：副标题与人数缓存清掉重算，否则返回后显示旧数据
    self.subtitleCache=nil;
    [MTFManager shared].countCache=[NSMutableDictionary dictionary];
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

// section: 0 开关 + 筛选方式, 1 批量操作, 2 列表, 3 排查
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if(s==0) return 2;
    if(s==1) return 2;
    if(s==3) return 2; // debug：排查区 2 行（诊断 + 页面记录）
    return 1 + (NSInteger)self.tags.count; // 首行=未设置标签
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    if(ip.section==0 && ip.row==1) return 56; // 筛选方式分段控件行
    if(ip.section==2) return 64; // 两行标签行：标题 + 成员名副标题
    return UITableViewAutomaticDimension;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if(s==0) return @"总开关";
    if(s==1) return @"批量操作";
    if(s==3) return @"排查";
    return [[MTFManager shared] filterMode]==1 ? @"不看以下标签的好友（可多选）" : @"按好友标签筛选（可多选）";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if(s==0) return @"开启后方可在信息流页按标签过滤；长按信息流页「我的头像」可随时打开本面板。";
    if(s==2){
        if(self.tags.count==0) return @"未读取到好友标签。请先在「通讯录 → 标签」中创建标签并添加好友。";
        if([[MTFManager shared] filterMode]==1)
            return @"点行左侧圆圈选择不看（点行同样切换）；点右侧 … 打开微信原生标签成员页（头像 + 字母索引）。被排除标签里的好友动态将从信息流里去掉，其余人不变。";
        return @"点行左侧圆圈选择筛选（点行同样切换）；点右侧 … 打开微信原生标签成员页（头像 + 字母索引）。";
    }
    return nil;
}

// 标签行右侧 … 按钮（微信标签页样式）：点它进成员页；行本身点按=勾选圆圈（didSelectRow）。
// v1.10.0 起行勾选不再用 UISwitch，改回微信原生圆圈（图一的样式）。
- (UIButton *)dotsButtonForRow:(NSInteger)row {
    UIButton *btn=[UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame=CGRectMake(0,0,28,28);
    [btn setImage:MTFDotsImage() forState:UIControlStateNormal];
    btn.tag=row;
    [btn addTarget:self action:@selector(openMembers:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// 副标题：前 8 个成员的备注/昵称，用 ", " 连接；成员多于 8 人时尾部加 ", …"。
// 每进一次页面算一遍并缓存（原生成员页可能增删成员，viewWillAppear 会清缓存重算）。
- (NSString *)subtitleForRow:(NSInteger)row {
    if(!self.subtitleCache) self.subtitleCache=[NSMutableDictionary dictionary];
    NSString *key = row==0 ? @"__untagged" : self.tags[row-1][@"name"];
    NSString *cached=self.subtitleCache[key];
    if(cached) return cached;
    MTFManager *m=[MTFManager shared];
    NSArray *contacts = row==0 ? [m untaggedContacts] : [m contactsForTagName:key];
    NSMutableArray *names=[NSMutableArray array];
    for(id c in contacts){
        NSString *n=MTFDisplayNameOfContact(c);
        if(!n.length) n=MTFUsernameOfMember(c);
        if(n.length) [names addObject:n];
        if(names.count>=8) break;
    }
    NSString *sub=[names componentsJoinedByString:@", "];
    if(sub.length && contacts.count>8) sub=[sub stringByAppendingString:@", …"];
    self.subtitleCache[key]=sub;
    return sub;
}

- (void)changeFilterMode:(UISegmentedControl *)seg {
    MTFManager *m=[MTFManager shared];
    [m setFilterMode:seg.selectedSegmentIndex];
    self.changed=YES; [m applyFilterChanged];
    [self.tableView reloadData]; // 列表行要换成新档位的勾选状态，标题/脚注也要换
}

- (void)pushVC:(UIViewController *)vc {
    if(self.navigationController) [self.navigationController pushViewController:vc animated:YES];
    else [self presentViewController:[[UINavigationController alloc] initWithRootViewController:vc] animated:YES completion:nil];
}

- (void)openMembers:(UIButton *)btn {
    NSInteger row=btn.tag;
    MTFManager *m=[MTFManager shared];
    if(row==0){ // 未设置标签的朋友不是一个标签，没有原生标签页，沿用自带名单
        MTFMemberListViewController *vc=[MTFMemberListViewController new];
        vc.title=@"未设置标签的朋友";
        vc.contacts=[m untaggedContacts];
        [self pushVC:vc];
        return;
    }
    if(row-1>=(NSInteger)self.tags.count) return;
    NSDictionary *tag=self.tags[row-1];
    NSString *name=tag[@"name"];
    // 优先用微信原生标签成员页（ContactTagNewDetailViewController：搜索栏 + A-Z 索引 + 头像行 + 添加/移出底栏）。
    // 数据模型就是原生的 ContactTagData（父类 ContactTagItem：ID + 名）+ 成员用户名列表。
    UIViewController *nativeVC=nil;
    @try {
        Class dataCls=objc_getClass("ContactTagData");
        Class vcCls=objc_getClass("ContactTagNewDetailViewController");
        if(dataCls && vcCls){
            id data=[[dataCls alloc] init];
            // 这三个原生方法在 tweak 里没有接口声明，直接调用会在 CI 被当成编译错误，统一走显式 objc_msgSend
            if([data respondsToSelector:@selector(setM_nsName:)])
                ((void(*)(id,SEL,id))objc_msgSend)(data, @selector(setM_nsName:), name);
            id tid=tag[@"id"];
            if([data respondsToSelector:@selector(setM_uiID:)] && [tid respondsToSelector:@selector(unsignedIntValue)])
                ((void(*)(id,SEL,unsigned int))objc_msgSend)(data, @selector(setM_uiID:), [tid unsignedIntValue]);
            NSArray *contacts=[m contactsForTagName:name];
            NSMutableArray *usernames=[NSMutableArray array];
            for(id c in contacts){ NSString *u=MTFUsernameOfMember(c); if(u.length) [usernames addObject:u]; }
            if([data respondsToSelector:@selector(setM_arrContactNameList:)])
                ((void(*)(id,SEL,id))objc_msgSend)(data, @selector(setM_arrContactNameList:), usernames);
            nativeVC=((id(*)(id,SEL,id))objc_msgSend)([vcCls alloc], @selector(initViewControllerWithContactTagData:), data);
            // 标题兜底：原生页应自带「名 (人数)」；若数据驱动标题失效，这里先给一个
            if([nativeVC isKindOfClass:[UIViewController class]] && !((UIViewController *)nativeVC).title.length)
                ((UIViewController *)nativeVC).title=[NSString stringWithFormat:@"%@ (%lu)", name, (unsigned long)usernames.count];
        }
    } @catch(__unused id e){ nativeVC=nil; }
    if(nativeVC){ [self pushVC:nativeVC]; return; }
    // 原生页不可用时回退自带名单（点成员仍可跳个人朋友圈）
    MTFMemberListViewController *vc=[MTFMemberListViewController new];
    vc.title=name;
    vc.contacts=[m contactsForTagName:name];
    [self pushVC:vc];
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    MTFManager *m=[MTFManager shared];
    if(ip.section==0){
        UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.selectionStyle=UITableViewCellSelectionStyleNone;
        if(ip.row==1){ // 筛选方式：只看这些 / 不看这些（切档不丢另一档的勾选）
            // v1.10.1 修超框：之前 frame 用 view 宽 -32，没扣 inset 分组 cell 自身的左右边距，
            // 控件右端比白卡多出 16pt。改约束布局：左右各贴 contentView 16pt，永远在卡内。
            UISegmentedControl *seg=[[UISegmentedControl alloc] initWithItems:@[@"只看这些", @"不看这些"]];
            seg.selectedSegmentIndex=[m filterMode];
            seg.translatesAutoresizingMaskIntoConstraints=NO;
            [seg addTarget:self action:@selector(changeFilterMode:) forControlEvents:UIControlEventValueChanged];
            [c.contentView addSubview:seg];
            [NSLayoutConstraint activateConstraints:@[
                [seg.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],
                [seg.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],
                [seg.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor],
                [seg.heightAnchor constraintEqualToConstant:28],
            ]];
            return c;
        }
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
        c.textLabel.text=ip.row==0 ? @"生成诊断信息" : @"页面记录（debug）";
        return c;
    }
    // 微信通讯录标签页样式：左侧圆圈勾选 + 两行（名 (人数) / 前 8 个成员名）+ 右侧 … 进成员页。
    // 每次新建，避免复用导致的文字错位；人数紧贴名字后、灰色括号，如「摄影师 (71)」。
    // 卡片样式（MTFStyleCardCell）早已预留 imageView 的分隔线位置，两行 cell 直接可用。
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.detailTextLabel.font=[UIFont systemFontOfSize:13]; // 官方副标题约 13pt（原 14pt 偏大）
    c.detailTextLabel.textColor=[UIColor grayColor];
    c.detailTextLabel.numberOfLines=1;
    c.detailTextLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    if(ip.row==0){ // 未设置标签的朋友
        c.textLabel.attributedText=MTFNameCount(@"未设置标签的朋友",[m untaggedCount]);
        c.detailTextLabel.text=[self subtitleForRow:0];
        c.imageView.image=MTFCircleCheck([m untaggedSelected]);
        c.accessoryView=[self dotsButtonForRow:0];
        return c;
    }
    NSDictionary *tag=self.tags[ip.row-1];
    NSString *name=tag[@"name"];
    c.textLabel.attributedText=MTFNameCount(name,[m memberCountForTag:tag]);
    c.detailTextLabel.text=[self subtitleForRow:ip.row];
    c.imageView.image=MTFCircleCheck([m isTagSelected:name]);
    c.accessoryView=[self dotsButtonForRow:ip.row];
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
    if(ip.section==3){
        if(ip.row==0){ [self showDiagnostics]; return; }
        MTFDiagnosticsViewController *vc=[MTFDiagnosticsViewController new];
        vc.text=MTFDebugPageLogText();
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nav animated:YES completion:nil];
        return;
    }
    if(ip.section==0) return;
    if(ip.section==1){
        if(ip.row==0) [m selectAll]; else [m clearAll];
        self.changed=YES; [m applyFilterChanged];
        [t reloadData]; return;
    }
    if(ip.row==0){ [m setUntagged:![m untaggedSelected]]; }
    else { NSString *name=self.tags[ip.row-1][@"name"]; [m setName:name selected:![m isTagSelected:name]]; }
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
    BOOL exclude=[m filterMode]==1;
    [r appendFormat:@"开关: %@  方式: %@  已选标签: %@  含未标签: %@\n",
        [m enabled]?@"开":@"关",
        exclude?@"不看":@"只看",
        exclude
            ? ([m excludedNames].count?[[m excludedNames] componentsJoinedByString:@", "]:@"(无)")
            : ([m selectedNames].count?[[m selectedNames] componentsJoinedByString:@", "]:@"(无)"),
        [m untaggedSelected]?@"是":@"否"];
    [m ensureSets];
    NSSet *fresh=exclude?[m freshBlockedSet]:[m freshAllowedSet];
    NSSet *cached=exclude?m.blockedUsernames:m.allowedUsernames;
    [r appendFormat:@"成员集合: 缓存 %lu 人 / 现算 %@ 人  已打标签总集 %lu 人\n",
        (unsigned long)(cached?cached.count:0),
        fresh?[NSString stringWithFormat:@"%lu",(unsigned long)fresh.count]:@"取不到(服务未就绪)",
        (unsigned long)(m.taggedUnion?m.taggedUnion.count:0)];
    if(fresh && cached && fresh.count!=cached.count)
        [r appendString:@"⚠️ 缓存与现算不一致: 缓存是旧的或被冷启动毒化\n"];
    ContactTagMgr *tm=[m tagMgr];
    for(NSString *name in (exclude?[m excludedNames]:[m selectedNames])){
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
