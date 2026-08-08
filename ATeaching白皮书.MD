# ATeaching白皮书

本文档面向后续维护和继续开发。目标是把 ATeaching 的整体结构、数据边界、关键流程、容易出问题的位置和维护原则说清楚。本文允许使用必要的技术名词，但尽量把每个名词对应到实际文件和功能。

---

# 一、项目定位

ATeaching 是一个以 macOS 为主，同时兼顾 iPadOS / iOS 的授课管理系统。它不是单一编辑器，而是由多个子系统组成：

- 授课流程系统
- 中心教案系统
- NodeMarkdown 结构化编辑器
- 普通 Markdown 编辑器
- 学生资料系统
- 课时统计系统
- 排课和周表系统
- 单列表格系统
- 画图系统
- PDF / HTML / 图片导出系统
- 同步、备份和回收系统

项目的核心设计原则是：

1. **本地文件优先**：所有关键资料都落盘为普通文件，方便迁移、备份和人工检查。
2. **中心教案优先**：教案是母本，上课随堂笔记可以反向改进母本。
3. **不破坏历史数据**：学生、机构改名或删除时，历史课时记录不应丢失。
4. **兼容旧数据**：设置和文档结构升级时必须兼容已有文件。
5. **课堂操作少打扰**：上课中保存、导出、同步尽量自动完成。

NodeMarkdown样式数据始终是`H1...H6 + body1...body5 + comment`十二个独立角色。旧JSON只有共享`body`时，解码层把它复制到五个正文角色；界面和后续保存不得再把五级正文合并。`NodeMarkdownRenderContract`统一规定每级固定缩进步长、固定编号宽度和固定编号间距，编辑器、HTML及PDF应从同一契约取值。

日常字符输入仍只允许局部处理。完整渲染仅用于文档样式改变和外部整篇正文替换这两类低频事务，以保证屏内屏外处在同一代样式。滚动入口同步渲染可见区并保留24行前后缓冲，不能等滚动停止才处理；视图拆除前先提交活动草稿并隐藏文本视图，禁止关闭动画展示附件源码恢复过程。

机构与课程快照的图标字段均为可选值，保证旧JSON直接解码。机构颜色推荐从固定高区分度色板中选择与现有颜色最远的一项；整体颜色整理只写`Setting-机构.json`，不改`LessonRecords.json`历史快照。课块图标用系统符号名持久化，以课块宽度80%透明叠放，不参与课块文字布局。

单列表格导出属于一次提交事务：先让活动`NSTextView`结束编辑并把Binding写回，下一轮主线程才能构造`SingleListExportSnapshotView`。直接在同一轮读取`rows`会遗漏尚在控件内部的最后输入。

档案目录监听与列表呈现必须分层。文件写入产生的连续目录事件先合并，再在后台重读条目签名；只有路径、名称、类型或目录属性真正变化时才替换SwiftUI列表。后台核对不得修改首次加载的`isLoading`，否则进度视图会使整个列表反复位移。

公式字符规范化是NodeMarkdown新旧管线和普通Markdown的共享边界。所有SwiftMath入口先通过`NodeMarkdownFormulaLatexNormalizer`，将希腊字母、常见变体、APL omega、微/欧姆符号和字母类数学符号转成SwiftMath已支持的LaTeX命令；CJK文字继续包装为`\\text{...}`并使用常规中文回退字体。

图片资源必须遵守所有权边界：章教案`Pic`是母本共享资源，随堂笔记只是引用者，任何单份随堂笔记都没有资格根据自身引用集合清理整个目录。禁止在实时保存和同步流程中执行跨目录垃圾回收；孤立图片只能由全工作区健康检查报告，默认不自动删除。

新H3包临时图片由“NodeMarkdown文档 + H3包”共同拥有。正文删除图片引用时，只允许把该文档自有临时目录中的明确文件放入撤回区。撤回区按文档路径隔离，事务顺序固定为：复制到撤回区、原子落盘原路径和暂存路径的对应记录、最后删除原文件。打开文档先恢复磁盘正文仍引用的图片；只有最终文档保存和同步明确成功后，才能整理该文档的撤回区。异步保存刚启动、写盘失败或软件异常退出时都必须保留恢复材料。

图片导入使用内容哈希文件名，但“同名文件存在”不能等价于“文件可用”。必须检查非零长度、大小限制和ImageIO实际解码，并使用原子替换，禁止先删旧文件再移动新文件。Markdown图片目标采用括号平衡解析，不能用遇到第一个`)`即结束的正则承担资源删除依据。

NodeMarkdown旧TextKit管线把中文输入法的marked text视为独立的未提交事务。组合期只重建UTF-16行坐标并记录所在Node，不写段落属性、不进入Node切换、不提交编辑草稿、不执行异步样式刷新。候选文字造成排版几何变化时，只使用`ensureLayout(forBoundingRect:in:)`完成可见区布局，再重画自绘的编号、背景条、高亮和下划线。只有定字后的文本才进入普通字符提交流程。

拼音组合边界必须同时约束协调器内部和SwiftUI外部入口。`updateNSView`在任何样式、搜索、元数据或正文同步之前先检查`hasMarkedText`；`applyStyle`也要独立检查，不能依赖调用者自律。候选期不向父页重复发布未变化的活动行。旧管线的对象链固定为`NSTextStorage -> NSLayoutManager -> NSTextContainer -> NSTextView`，不允许预建TextKit 2对象后再依赖`NSTextView`暗中替换。

自绘层不能假设`textDidChange`一定早于绘图。`setMarkedText`可以先改变字符长度并触发绘图，因此编号、背景条和下划线必须在每次绘制中验证行索引是否覆盖当前存储全长。缓存过期时使用当前存储的只读临时索引解析level，不得因旧字符坐标匹配失败而降级为正文。

---

# 二、主要目录和文件

## 1. Swift 源码目录

主要源码位于：

```text
ATeaching/
```

这里包含 SwiftUI 页面、业务服务、数据模型、导出逻辑和编辑器实现。

## 2. 说明与支持页面

项目根目录中有：

```text
index.html
support.html
```

用于产品介绍和支持页面。

## 3. 开发记录

项目根目录中有：

```text
Ateaching开发记录.MD
```

后续每次重要改动都应写入这个文件。规则是每次新增一个 H1 块，标题写编号和改动主题，正文先用中文说明意义，再补充必要技术细节。

## 4. 排课独立项目占位

根目录下有：

```text
排课/
```

这是未来把排课能力剥离成 Flutter / Web / iOS / Android / Windows / macOS 多端应用的预留目录。当前只应作为独立项目的起点，不应反向污染 ATeaching 主工程。

## 5. 构建产物与暂存文件的统一管理

为保持项目目录干净（尤其是项目位于 iCloud 云盘时，项目树内的构建中间件会被 iCloud 当作资料同步放大），统一约定：每个 App 在 `/Users/Witten/Downloads/Temp/SoftWare/XcodeTemp/` 下建立自己名字的文件夹作为暂存目录，构建产物、中间件、临时文件一律放那里。ATeaching 的暂存目录：

```text
/Users/Witten/Downloads/Temp/SoftWare/XcodeTemp/ATeaching
```

- 图形界面构建位置由共享设置 `ATeaching.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` 指定，指向该暂存目录。
- 命令行构建固定通过 `Scripts/build.sh` 执行，内部统一加 `-derivedDataPath` 指向同一目录；`clean` 子命令可清空该 App 的暂存目录。
- 项目目录内（含 `Vendor/SwiftMath` 包目录）不应出现任何 `build` 目录；源码树中的临时构建产物一律直接删除。
- 注意：不要用 pbxproj 工程级 `SYMROOT` 收拢输出，它会触发 legacy build locations 导致 Swift 包依赖无法解析。

---

# 三、App 入口与窗口管理

## 1. 应用入口

核心入口在：

```text
ATeaching/ATeachingApp.swift
```

它负责：

- 创建主窗口
- 管理 macOS AppDelegate
- 处理外部打开 Markdown 文件
- 控制主窗口和 Markdown 独立窗口的关系

维护注意点：

- 从访达打开 `.md` 文件时，不应额外打开授课主窗口。
- 多个外部 Markdown 文件应尽量进入同一个 Markdown 标签窗口。
- 主窗口应保持唯一，不能因为外部文件打开而创建多个主窗口。

## 2. 主界面

核心主界面在：

```text
ATeaching/ContentView.swift
```

它负责组织顶部入口和当前子页。标题显示相关逻辑可参考：

```text
ATeaching/AppDisplayTitle.swift
```

---

# 四、数据根目录与文件策略

ATeaching 使用本地文件作为主要数据载体。常见数据会放在用户选择或软件管理的数据根目录中。

常见逻辑目录包括：

```text
系统/
系统/课单/
系统/教案/
系统/暂存/
```

重要规则：

1. 不要把用户数据写死到工程目录。
2. 所有自动生成文件都要有稳定路径。
3. 删除类操作必须明确区分“设置删除”和“历史数据删除”。
4. 历史记录尽量只追加或按明确规则修改，不要因为当前设置变化而重写历史。

---

# 五、学生系统

## 1. 主要文件

学生相关代码包括：

```text
ATeaching/TeachingAddStudentSheet.swift
ATeaching/TeachingStudentSettingsStore.swift
ATeaching/TeachingStudentProvisioningService.swift
ATeaching/TeachingStudentRenameService.swift
ATeaching/TeachingStudentBackupSheet.swift
ATeaching/TeachingStudentBackupService.swift
ATeaching/TeachingStudentProfileSettingsView.swift
ATeaching/TeachingStudentSystemSettingsView.swift
```

## 2. 学生初始化

学生初始化现在包含统计页和同步文件夹页。需要兼容早期只有较少页面的旧设置文件。

维护规则：

- 读取旧数据时不能因为字段缺失而覆盖为空。
- 保存学生设置时不能丢失第 6 页统计设置和第 7 页同步设置。
- 从授课入口添加学生时，不应强行要求填写所有统计项。

## 3. 学生改名

学生改名需要影响：

- 学生显示名
- 学生档案文件夹及自动生成文件
- 学生信息和上课信息的姓名字段
- 学生个人同步文件夹及自动导出文件
- 成课、排课和周表中同一学生 ID 对应的显示名

`TeachingStudentRenameService` 把学生 UUID 视为身份，姓名只是显示值。`LessonRecords.json`、`排课.json` 和 `周表.json` 只修改 `studentID` 完全相同的记录；缺少 ID 的旧记录保持原样，不根据旧姓名猜测。

档案内只改名精确的自动文件：`随堂笔记_<姓名>.CSV`、`学生信息_<姓名>.CSV`、`上课信息_<姓名>_<日期>.CSV` 和 `教案_<教案>_完成情况_<姓名>.CSV`，并更新其 `[META_TITLE]`。学生信息和上课信息的姓名优先依靠设置的行 UUID；旧数据只对极少数精确标题回退，禁止用“包含姓名”的模糊规则。

同步目录只处理学生 profile 中实际的 `编号-姓名` 目录和精确的自动导出文件；全局 `studentSystem.syncBaseFolderPath`、UUID 命名的基线/冲突/撤回文件、历史日志和用户自建文件不变。

改名是一次跨文件事务：先检查姓名、忽略大小写的重名、档案存在性、同步目录可用性和所有目标冲突；通过后才写 CSV、移动文件、保存三份课单和设置。任意步骤失败会逆序移回文件并恢复原始字节和数据快照。目标已存在时永不覆盖，旧档案丢失时永不创建空目录。活动授课/笔记会话或后台课程任务存在时禁止改名。

## 4. 学生备份

备份的业务含义是“从当前学生列表移除，并把文件夹放起来”。它不是简单删除。

应保证：

- 学生列表移除。
- 总设置中移除。
- 学生文件夹被移动到备份位置。
- 历史课时记录不动。

---

# 六、教案系统

## 1. 主要文件

教案管理相关文件包括：

```text
ATeaching/LessonPlanManagementView.swift
ATeaching/LessonPlanStorage.swift
ATeaching/TeachingLessonPlanSystemSettingsView.swift
```

## 2. 教案与章节

教案系统按教案名、章节名组织。NodeMarkdown 教案编辑时，图片应放到：

```text
系统/教案/<教案名>/<章教案名>/Pic/
```

维护时要注意：上课状态和教案编辑状态的图片路径规则不同，但都必须生成可用的相对链接。

---

# 七、NodeMarkdown 文档模型

NodeMarkdown 的持久化模型将 `Prefix` 与 `Content` 分列保存，内存模型也将 `NodeMarkdownNode.level` 与 `text` 分开。新旧 TextKit 管线的编辑缓冲区必须与该模型一致：`NSTextStorage` 只容纳各 Node 的 `Content` 和行分隔符，不容纳 `### `、`- `、`> ` 等层级前缀。

编辑器加载快照必须原子地包含正文和等行数的行元数据。不得先把正文交给 TextKit，再异步补充层级；即使正文没有变化，只要行元数据变化，新旧管线都必须重新计算对应行的排版。新管线的布局缓存比较完整行元数据，旧管线在元数据更新后主动刷新样式，避免初始页面全部退化为正文层级。

焦点只由用户输入事务决定。新管线必须先执行NSTextView/TextKit2原生点击命中，禁止重新引入按绘制坐标手算字符位置的第二套点击系统。结构命令完成后，样式刷新、解析、防抖保存和附件渲染都不得另行选择文首或文末。正文Binding与行元数据必须在同一次主线程调用中发布，避免中间无效状态触发外部全文替换。

TextKit2新管线必须只有一个正文所有者：显式创建的`NSTextStorage`作为唯一存储，依次连接`NSTextContentStorage`、`NSTextLayoutManager`、`NSTextContainer`和`NSTextView`。任何代码都不得在已连接`textStorage`后给`NSTextContentStorage.attributedString`重新赋值，因为该操作会解除TextView的可编辑存储，造成布局仍持有正文而`NSTextView.string`为空。正文读取、范围修改、属性修改、撤销和外部载入都必须使用唯一存储；Debug构建应断言整条对象链身份一致。

新管线样式系统不得通过构造新`NSMutableAttributedString`再调用全文`setAttributedString`来刷新显示。全量样式只能在唯一存储上原位恢复附件锚点、重置属性和应用行样式；单行源码/渲染切换只能触碰目标行。公式图片附件的首字符切换必须保持UTF-16长度不变。`markedRange`存在时，输入法独占组合文本，样式、附件、快捷输入、行重建和外部正文同步全部避让；编辑器只能设置`typingAttributes`，在组合提交后再执行一次正常文本事务。

新管线的本地编辑会话是正文与行元数据的临时唯一写入者。每次向SwiftUI发布正文时递增本地修订序号，并记录当前最新正文；只有外部回送与该最新正文完全一致时才能确认修订。在确认前到达的旧正文、旧`editingRowIndex`和旧行元数据必须被拒绝，禁止调用全文替换。失焦后且没有待确认本地修订时，显式外部同步才可以装载新文档。

新管线结构焦点统一表示为`Node UUID + Node内UTF-16偏移 + 选择长度`，并集中由`NodeMarkdownTextKit2FocusTransaction`管理。Enter、行首Backspace、Tab/Shift+Tab、H3相邻新行及Undo/Redo先完成正文和行元数据事务，再按Node身份恢复选择；用户真实点击、方向键选择或下一次普通输入开始时释放旧事务。程序内部设置选择必须处于样式更新保护中，不能被选择代理误判为用户操作。

布局表必须覆盖持久化模型中的每一个Node。正文以换行结尾时，最后的空Node必须建立`location == documentLength, length == 0`的正式行布局，并取得对应元数据；`currentRowIndex`和行定位必须显式识别这一零长度行。Enter与行首Backspace只能使用布局的`contentRange`拆分或合并，不得再用`NSString.lineRange`推测文末空行。

唯一`NSTextStorage`仍是新管线唯一正文所有者，但允许维护一个等UTF-16长度的源码读取快照以换取高频性能。快照只能由全文载入、原生`shouldChangeTextIn`投影、受控范围替换和异常重建四个入口更新；附件挂载与样式操作不得修改快照。`documentString()`必须直接返回快照，禁止在每次按键时枚举整篇附件属性。结构事务和全文载入后以深校验重建源码核对快照，普通字符输入只校验长度、行范围和选择范围。

字符级编辑不得重建整篇布局。当前行重新计算后，后续行只更新字符偏移；普通字母和普通删除不重新应用行样式。由于编辑缓冲区已不含层级前缀，不得恢复“行首若干字符可能改变层级”的旧判断。Markdown/HTML分隔符、换行和快捷输入可以刷新当前行。搜索词改变允许全篇更新搜索标记；活动搜索项、活动行和编辑行变化只能刷新涉及的旧行与新行。

Debug验收必须覆盖：`NSTextView`、`NSTextStorage`、`NSTextContentStorage`和`NSTextLayoutManager`仍属于同一对象链；源码快照和存储UTF-16长度相同；行布局连续并覆盖全文；所有选择位于正文内；结构事务后从附件属性恢复出的源码与快照完全一致。轻校验可进入每次输入路径，深校验不得进入普通按键热路径。

旧管线中的公式和图片只允许使用等长附件表示：源码首字符可临时成为U+FFFC附件占位符，其余源码字符保持原位并隐藏。恢复源码只能原位替换该首字符，禁止为恢复附件替换整行或整篇NSTextStorage。所有样式和附件操作都属于程序内部更新，不得向焦点状态发布选择变化。Enter和行首Backspace的最终焦点以Node UUID与Node内偏移表示，并跨过SwiftUI状态回写和样式重排；下一次真实用户选择或输入开始时才释放该事务。

编辑器传回的合法且唯一的行UUID是身份事实，包括旧文档中不存在、由Enter刚创建的新UUID。解析器必须原样采用，只有UUID无效或同一快照内重复时才能生成新UUID；否则结构命令建立的焦点目标会在解析后失去对应Node。

每行由 `NodeMarkdownTextKitRowMetadata` 承载 Node UUID、level、SourceID、SourceFile 和 H3 保护状态。排版、缩进、段前段后、字体和左侧标志均从这份元数据计算。编辑器不得再通过正文开头反向猜测层级，因为用户正文可以合法地以 `# ` 或 `- ` 开头。

结构命令同时修改正文与行元数据：Enter 保留原 Node 身份并为拆出的后一行生成新 UUID；行首 Backspace 保留前一 Node 并回收后一 Node；Tab/Shift+Tab 只改 level。受保护 H3 的行首合并仍被禁止，H3 上的 Tab/Shift+Tab 按既定规则生成 H4/H2 空 Node。撤销快照必须将正文和元数据作为一个整体恢复。

`NodeMarkdownPrefixCodec` 仍是文件边界协议：读旧 CSV 时把 `Prefix` 解码为 level，写 CSV 时由 level 生成 `Prefix`。它不得再参与编辑器的焦点、选择和文本变更。

## 1. 主要文件

NodeMarkdown 核心文件包括：

```text
ATeaching/NodeMarkdownDocument.swift
ATeaching/NodeMarkdownEditorView.swift
ATeaching/NodeMarkdownSettings.swift
ATeaching/NodeMarkdownRenderContract.swift
ATeaching/NodeMarkdownPackageCleaner.swift
ATeaching/NodeMarkdownImageAssetService.swift
ATeaching/NodeMarkdownFormulaLatexNormalizer.swift
```

## 2. 文档结构

NodeMarkdown 的核心思想是：文档由一组节点组成。每个节点至少包含：

节点 UUID 是行的永久身份，不是根据行号或文字重新计算的临时值。编辑文字和调整普通节点层级时保留 UUID；回车或插入产生的新行必须创建新 UUID；删除使 UUID 退出文档但不供后续新行复用；剪切移动完整保留包内 UUID；复制则为包内每个节点生成新 UUID，复制的 H3 清空母本来源并成为新包。

文本管线回写 Node 时，每个旧 UUID 在一次解析中只能被一行领取。编辑器明确传回的行身份优先并提前预留；位置后备不得重复领取身份，也不得让 H3 与非 H3 跨边界继承身份。写盘和同步前必须验证整篇 UUID 唯一；非 H3 不得携带来源；来源完整的 H3 必须满足节点 UUID 与 `SourceID` 相同。旧文件中只有一半来源信息的 H3 可以暂存并交给同步流程修复。检查失败时保留内存和原文件，禁止继续写盘或向母本传播。

全库历史身份修复由`TeachingLessonWashService`负责。服务必须先读完全部正式教案、随堂笔记和完成清单，在内存中形成确定的旧身份到新身份映射，然后才能写盘。正式教案的Node UUID要求全库唯一；不同学生随堂笔记中的同一母本包允许共享母本UUID，但每一份随堂笔记内部必须唯一。

重复H3不能只按UUID迁移，因为损坏数据中同一个UUID可能属于多个正式H3。匹配顺序是：`SourceFile+SourceID`、包含文件的旧身份映射、H3根UUID、全库唯一标题、全包内容唯一。任何阶段出现多个候选都停止自动处理。成功匹配后必须同时令随堂根UUID、SourceID和母本H3 UUID相等，并修正SourceFile。

`上课收集/上课收集.CSV`是洗教案过程的只读边界。无法唯一迁回正式教案的上课收集包必须保留并进入报告，不能沿用旧SSC工具的自动删除规则。完成清单应从清洗后的母本重新生成，旧Status通过同一身份映射继承；清洗后随堂笔记里实际存在的正式H3也必须标为完成。无法找到所属正式教案文件夹时禁止写入空清单。

清洗后的正式母本写盘前必须通过全库UUID检查；随堂笔记逐文件通过`NodeMarkdownIdentityPolicy`检查。不能通过检查的文件保持原样，并在`系统/暂存/洗教案/`报告中列出。

- 节点 ID
- 层级
- 文本内容
- 渲染状态
- 来源文件
- 来源节点
- 可能的图片、公式、样式信息

上课时从母本教案插入的 H3 包，需要保留来源信息。新包插入母本后，随堂笔记中的对应包必须回填来源文件和来源节点，否则之后仍会被误判为“新包”。

## 3. 层级系统

层级包含：

- H1 到 H6 标题
- 正文 1 到正文 12

正文层级以前部分共用设置，现在正文第 7 到第 11 级也独立。读取旧设置时必须补默认值，不能破坏旧 setting 文件。

## 4. 源码状态与渲染状态

NodeMarkdown 支持“当前行源码编辑，其他行渲染显示”。

关键规则：

- 点击某行后，该行进入源码编辑。
- 光标必须进入点击位置。
- 当前正在编辑的行不能因为 Tab、输入或局部刷新被强行渲染。
- 失焦或切换行时，旧行才重新渲染。

---

# 八、NodeMarkdown 双管线

NodeMarkdown 目前存在两套显示管线：

1. 旧管线：基于原有 TextKit 处理。
2. 新管线：TextKit2 方向的新实现。

相关文件包括：

```text
ATeaching/NodeMarkdownTextKitEditor.swift
ATeaching/NodeMarkdownTextKit2NewlineCommands.swift
ATeaching/NodeMarkdownTextKit2Delegate.swift
ATeaching/NodeMarkdownTextKit2Renderer.swift
ATeaching/NodeMarkdownTextKit2Layout.swift
```

维护原则：

1. Debug 中选择 TextKit2 时，应尽量使用纯 TextKit2 新管线。
2. 旧管线修复不要误伤新管线。
3. 新旧管线的视觉合同要一致，包括编号标志、文字、公式、高亮、下划线、图片。
4. 光标位置必须以可输入区为准，不能进入编号标志或缩进禁入区。
5. 从公式行回车后，必须先把光标锚定到新行可输入区，再允许渲染刷新。刷新后还要根据结构锚点恢复，避免 selection 被附件或公式重排推到下一行禁入区。

高风险区域：

- 从公式行回车。
- 从下一行行首 Backspace 合并到上一行。
- Tab / Shift+Tab 改层级后保持光标。
- Command+Z 恢复后刷新显示。
- 保存后重新渲染图片和公式。

---

# 九、公式渲染

## 1. 主要文件

公式相关文件包括：

```text
ATeaching/NodeMarkdownFormulaLatexNormalizer.swift
ATeaching/NodeMarkdownFormulaRenderer.swift
```

以及 NodeMarkdown 渲染、PDF 导出、HTML 导出中的公式处理逻辑。

## 2. 支持目标

公式应支持：

- 常见 LaTeX 表达式
- 中文
- 希腊字母
- 比较符号
- 特殊符号
- `…`
- 带可选参数的根式，例如 `\sqrt[n]{...}`

如果公式中包含普通中文，需要在送入渲染前做规范化处理，避免中文被当成 LaTeX 命令的一部分。

公式渲染使用 SwiftMath 时，中文、圈号数字等 fallback 字体必须使用常规字重，不能因为系统字体回退被渲染成粗体。旧 TextKit 管线和 TextKit2 管线都通过 `NodeMarkdownFormulaLatexNormalizer` 共享符号规范化，常见全角数学符号、全角等号、箭头、省略号等应在进入渲染前转换成可识别的 LaTeX 或文本形式。

## 3. 对齐要求

公式、普通文字、编号标志、高亮背景应以视觉中心对齐，而不是简单按底线对齐。

维护时要统一以下场景：

- 旧管线显示
- 新管线显示
- PDF 导出
- HTML 导出

禁止只靠手动常数反复微调。应尽量基于字体尺寸、图像尺寸、行高和基线计算。

---

# 十、图片系统

## 1. 主要文件

图片处理主要看：

```text
ATeaching/NodeMarkdownImageAssetService.swift
```

以及编辑器插入图片、导出 PDF / HTML 的相关代码。

## 2. 规则

上课状态图片应进入当前随堂笔记对应的图片目录。教案编辑状态图片应进入：

```text
系统/教案/<教案名>/<章教案名>/Pic/
```

图片语法示例：

```markdown
![image](Pic/img-xxxx.jpg){width=600}
```

宽度有效下限应支持到 1。导出 PDF 时图片缩放要基于 NodeMarkdown 内设置的宽度，再乘以 PDF 缩放比例。

## 3. 删除和撤回

删除图片时，不应立即永久删除。应先移动到：

```text
系统/暂存/图片/
```

并记录原路径，方便 Command+Z 恢复。关闭 NodeMarkdown 编辑器或下课时清空暂存图片。

---

# 十一、NodeMarkdown 导出

## 1. 主要文件

导出相关文件包括：

```text
ATeaching/NodeMarkdownPDFExporter.swift
ATeaching/NodeMarkdownScaledPDFExporter.swift
ATeaching/NodeMarkdownHTMLExporter.swift
ATeaching/NodeMarkdownTextKitPDFExporter.swift
ATeaching/TeachingNodeMarkdownPrintPipeline.swift
```

## 2. 导出格式

NodeMarkdown 应支持导出：

- PDF
- HTML
- MD

导出按钮应使用系统导出窗口，用户可以选择保存位置。

## 3. 样式要求

导出要尽量还原编辑器内样式：

- 背景色
- 字体
- 字号
- 字色
- 加粗
- 斜体
- 蓝色下划线
- 圆角高亮
- 图片
- 公式
- 编号标志
- 层级缩进

如果 NodeMarkdown 样式中设置了背景色，PDF 和 HTML 都应使用该背景色。否则按浅色模式白底导出，不应因为系统深色模式把黑字强行变白。

## 4. 缩放

PDF 导出的文字和图片缩放比例由设置中的 NodeMarkdown PDF 缩放比例统一控制。公式也必须使用相同缩放原则，不能比文字和图片明显更大。

---

# 十二、普通 Markdown 编辑器

## 1. 主要文件

普通 Markdown 相关文件包括：

```text
ATeaching/MarkdownEditorView.swift
ATeaching/MarkdownExportRenderer.swift
ATeaching/ExternalMarkdownTabWindowView.swift
```

## 2. 能力范围

普通 Markdown 支持：

- 源码编辑
- 双区域编辑：左 TextKit2，右 Web 预览
- 搜索
- 导出 PDF
- 导出 HTML
- 导出 MD
- 从访达直接打开
- 多文档标签页

“即时渲染”代码保留为 Markdown 旧管道，不再作为常用入口。后续维护应优先保证 TextKit2 编辑区和 Web 预览区一致。

双区域跟随不使用滚动百分比。左侧 TextKit2 与右侧 Web 都以源文本行号为共同锚点：左侧根据视野中线计算源行，右侧 Web 渲染块记录 `startLine`，滚动停止后双方用中线行号互相定位。打字停止约 3 秒后也应重新发布一次左侧中心行，以便预览区追上最新内容。

## 3. 性能原则

大文件编辑时，输入和删除都要尽量避免全量刷新。

对于行内删除：

- 如果当前行仍存在。
- 如果没有改变标题结构。
- 如果没有改变图片、公式、链接等跨结构内容。

就应尽量只处理当前行，避免重算整个文档。

搜索框也应避免每输入一个字就全量搜索，应在点击搜索按钮或按回车后执行。

## 4. 数字编号导出

普通 Markdown 的层级数字编号以两个空格为一层。同层编号的判断键是：

```text
缩进 + 数字前缀
```

因此 `2. ` 和 `  1. ` 属于不同层级，不允许在导出 PDF 或 HTML 时被合并成同一串编号。Web 渲染前会保护显式数字编号行，保留源码中写出的数字和缩进，避免 marked 或浏览器列表自动重排。

## 5. 档案页文件管理

档案页新增统一文件操作：

- 右键改名、删除、移动。
- 右上角新建文件、新建文件夹、多选、刷新。
- 多选后可批量删除、批量移动、组成文件夹。
- 当前目录使用文件系统监听器监听访达改动，收到写入、改名、删除等事件后刷新目录。

移动使用 `ArchiveStorage.moveItem` / `moveItems`，目标重名时自动生成 `-2`、`-3` 后缀，避免覆盖用户文件。

教案文件夹和章教案的改名由 `TeachingLessonRenameService` 接管。它将教案相对路径视为跨文件身份的一部分，在一次事务内迁移随堂H3和完成清单的 `SourceFile`、中央教案模板、学生备份、同步基准、可继续处理的冲突记录、章图片目录及正文图片链接。被改名CSV的 `[META_TITLE]` 同步更新。事务执行前检查全部目标冲突；失败时恢复原始文件和移动。改名后清除插包撤回快照，历史日志、清洗报告和回收站不做追溯改写。

---

# 十三、授课流程系统

“授课-教案”由 `LessonPlanManagementView` 展示根层教案文件夹和一级章教案文件。两类条目右键只暴露改名、删除；`LessonPlanStorage` 再按目录深度验证目标，防止其他目录绕用接口。改名经名称输入和影响确认后进入 `TeachingLessonRenameService`；删除经影响确认后进入软件回收站。活动授课或笔记会话存在时禁止执行。

## 1. 主要文件

授课流程相关文件包括：

```text
ATeaching/TeachingHomeView.swift
ATeaching/TeachingCoursePageView.swift
ATeaching/TeachingCourseWorkflowService.swift
ATeaching/TeachingCoursePackageSyncEngine.swift
ATeaching/TeachingCoursePackageStateEngine.swift
ATeaching/TeachingCoursePackageChangeTracker.swift
ATeaching/TeachingCourseClassSessionCenter.swift
ATeaching/TeachingCourseJobCenter.swift
ATeaching/TeachingCourseConsistencyScheduler.swift
ATeaching/TeachingCoursePDFExporter.swift
ATeaching/TeachingAnnotationOverlay.swift
```

## 2. 开课

进入学生授课页不应创建课反或上课记录。只有点击开课才创建。

开课后：

- 建立本节课上下文。
- 准备随堂笔记。
- 如果统计开启且学生设置完整，写入课时记录。
- 成课只允许由排课记录在时间经过后转入；开课不再生成成课。

## 3. 自动课反

随堂插入 H3 包时，课反“上课内容”栏应写入：

```text
详细内容：
1.<第一项>；2.<第二项>；3.<第三项>；
```

后续继续插入时，应沿用已有编号继续写。第一次添加后，下方留一行空白。

## 4. 随堂 H3 完成清单

学生每个教案的完成清单是随堂 H3 插入权限来源，不只是展示状态。

- 只有 `Status=0`、`Level=3`、且 `SourceFile/SourceID` 都不为空的行可以插入。
- UI 提交前必须过滤不可插入行。
- 服务层插入前必须重新读取磁盘完成清单，以最新 `Status` 为准，防止旧窗口或旧选择重复插入。
- 插入成功后，对应行必须写成 `Status=1`。
- 如果随堂笔记已经存在同 `SourceFile + SourceID` 的 H3 包，也应把对应完成清单行写成 `Status=1`，让清单和随堂笔记保持一致。

## 5. 脏包同步

课堂中修改过的母本包称为脏包。下课、关闭或自动保存时，应把脏包同步回母本。

脏包方向必须是“随堂笔记写回母本”。准备上课或刷新随堂笔记时，如果随堂 H3 根节点时间不早于母本 H3 根节点，不能用母本覆盖随堂包，否则会把课堂刚修改的内容冲掉。只有母本明确更新且随堂包未更新时，才允许从母本刷新到随堂。

同步前必须清洗空行：

- 删除多余空行。
- 如果焦点在被删除空行上，应失焦。
- 清洗后再写回母本。

## 6. 新包入库

随堂笔记中新写的 H3 包，如果来源文件和来源节点为空，可以作为新包插入母本。

插入母本后，必须立刻回填随堂笔记中该包的来源文件和来源节点。否则它会继续被识别为新包，导致重复插入。

## 7. 上课批注图层

上课会话的随堂笔记编辑器左上角按钮组右端有批注按钮群：批注（笔）、橡皮、清除。批注功能由独立文件`TeachingAnnotationOverlay.swift`承载，主编辑器只做状态挂载：

- `TeachingAnnotationController`：批注状态唯一事实，持有激活状态、当前工具（笔/橡皮）、笔划数和清空令牌。批注激活且当前工具已高亮时再点同按钮=清空并关闭；激活状态下笔/橡皮互相切换；清除键在无笔划时禁用。
- `TeachingAnnotationToolbarControl`：批注/橡皮/清除三个工具栏按钮，激活工具高亮为强调色。
- `TeachingAnnotationCanvasView`：原生覆盖画布，挂在编辑器上方图层。鼠标按下事件被画布拦截，正文不再响应点击；`scrollWheel`与`magnify`转发给底层滚动视图，滚动不受影响。
- 批注笔画保存在文档坐标系中，绘制时按当前滚动偏移换算回屏幕坐标，因此批注随页面滚动同步位移。
- 橡皮按整条笔画擦除：点击或拖过命中半径内的笔画即删除整条。
- 批注是临时内容：关闭批注状态或点击清除即清空，不写入 NodeMarkdown 正文、不参与保存与导出；画布随批注状态销毁。
- 批注颜色当前固定为红色，线宽 3 点；iOS 平台无批注图层。

---

# 十四、课时统计系统

## 1. 主要文件

统计系统相关文件包括：

```text
ATeaching/TeachingLessonStatisticsSubpageView.swift
ATeaching/TeachingLessonStatisticsStore.swift
ATeaching/TeachingLessonStatisticsModels.swift
ATeaching/TeachingInstitutionListPanel.swift
ATeaching/TeachingInstitutionDataSheet.swift
ATeaching/TeachingInstitutionEditorSheet.swift
ATeaching/TeachingLessonPlanningStore.swift
ATeaching/TeachingLessonPlanningBoardView.swift
ATeaching/TeachingLessonScheduleBuilder.swift
ATeaching/TeachingLessonScheduleWeekView.swift
ATeaching/TeachingLessonEditorSheet.swift
```

## 2. 数据文件

机构设置保存为 JSON，通常位于设置区域的：

```text
Setting-机构.json
```

已经完成的课保存到：

```text
系统/课单/
```

排课保存到：

```text
系统/课单/排课.json
```

周表保存到：

```text
系统/课单/周表.json
```

## 3. 课记录字段

一条课记录应包含：

- 记录 ID
- 开始时间
- 结束时间
- 学生 ID
- 学生名称
- 学生年级
- 机构 ID
- 机构名称
- 单价
- 机构颜色

学生名和机构名是快照，用于显示。ID 用于改名时定位。删除学生或机构不应删除历史课记录。

时间建议使用 ISO 8601 字符串存储，显示时再格式化。

## 4. 价格计算

课时价格指 2 小时价格。

计算方式：

```text
总价 = 课时价格 * 实际小时数 / 2
```

总价实时计算，不应作为单独字段长期存储。

## 5. 冲突判断

冲突条件：

```text
newStart < oldEnd && newEnd > oldStart
```

因此 8:00-10:00 与 10:00-12:00 不冲突。

## 6. 成课

成课表示已经完成的课。它从上课单中提取并展示。

成课页面现在只保留一种形式：上面图形表，下面文字统计。统计子页中不再需要单独的“修改”入口。

## 7. 排课

排课是未来课程安排。现在采用横向月表，从 1 号一直到月末。

排课要求：

- 可以显示超过本月的月份。
- 再次进入排课时保持上次月份。
- 双击月份回到本月。
- 过去时间应锁定。
- 过去课程由成课记录覆盖显示。
- 排课进入成课时优先级低，遇到冲突直接不加入。

## 8. 周表

周表是一周模板，用于快速插入排课。

它应支持：

- 选择学生
- 刚需|生活占位
- 插入课程
- 拖动课程
- 修改课程
- 删除课程
- 导出周表图片
- 导出机构周可用

---

# 十五、机构系统

## 1. 机构数据

每个机构包含：

- ID
- 名称
- 颜色
- 默认价格
- 备注

机构名称不允许重名。

## 2. 删除机构

删除机构时：

1. 从机构设置中删除。
2. 查找学生设置中使用该机构的学生。
3. 删除前二次确认，并列出这些学生。
4. 清空这些学生的机构和课时价格设置。
5. 不修改历史上课单。

## 3. 机构数据页

机构数据页从成课记录计算，不从当前机构设置推导。这样即使机构改名、改色或删除，历史记录仍可按快照显示。

复制文本时要用空格对齐，不用 tab。输出字段包括：

```text
日期 | 星期 | 时间 | 学生 | 小时
```

---

# 十六、排课导出与可用时间图

## 1. 图形导出

成课、排课、周表都支持导出图形课表。

导出图应满足：

- 背景为左上墨绿色、右下金色的渐变。
- 圆角区域外透明，不要白边。
- 字体默认黑色。
- 每节课的格子宽高与 App 内一致。
- 学生名字必须尽量完整显示，允许两行。
- 31 号必须完整显示，右侧留余量。

## 2. 可用时间图

机构可用图：

- 保留该机构课程。
- 其他机构占用时间用红色区域标出。
- 红色区域内显示占用图标和具体时间。

月可用图：

- 不针对机构。
- 所有课程都作为占用状态显示。

周可用图：

- 选择某一周后导出。
- 完整显示该周。

---

# 十七、单列表格系统

## 1. 主要文件

单列表格相关文件包括：

```text
ATeaching/SingleListDocumentEditorView.swift
ATeaching/SingleListTemplateEditorView.swift
ATeaching/SingleListTemplatePropagationService.swift
ATeaching/SingleListAppearanceSettings.swift
ATeaching/SingleListVisualStyle.swift
ATeaching/SingleListExportSnapshotView.swift
```

## 2. 模板传播

每个单列表格可以绑定一个模板。模板变化后，需要查找使用该模板的表格。

识别方式：

```text
[META_TEMPLATE]
```

更新规则：

1. 先暂存旧表。
2. 新表结构按模板新行生成。
3. 新表每一行使用模板行的 UUID 和 keyname。
4. 内容用 UUID 去旧表里找。
5. 找到相同 UUID，则保留旧内容。
6. 模板删除的行自然消失。
7. 模板新增的行内容为空。

这能保证模板更新时尽量不丢用户已经填写的内容。

## 3. 背景设置

背景设置不是单列表格专用，而是全局背景设置。

当前至少包括：

- 渐变背景：浅色草绿到淡金，深色墨绿到普鲁士蓝。
- 纯色背景：单列表格使用原有设置，其他区域保持纯色。

NodeMarkdown 编辑器如果已经有自己的背景设置，应尊重 NodeMarkdown 的背景，不强行套全局背景。

---

# 十八、画图系统

## 1. 主要文件

画图相关文件包括：

```text
ATeaching/NodeMarkdownDrawingBoardSheet.swift
ATeaching/DrawingBoardSettingsStore.swift
ATeaching/DrawingSnapEngine.swift
```

## 2. 功能范围

画图系统支持：

- 画笔
- 橡皮
- 文字
- 形状
- 三角形顶点调整
- 方形和圆形旋转
- 坐标系臂长调整
- 选择工具
- Backspace 删除
- Command+C / Command+V 复制粘贴
- Command+Z / Command+Shift+Z 撤回恢复

## 3. 吸附

吸附目标包括：

1. 点到点。
2. 点到线。
3. 线到线近似垂直。
4. 直线边图形到直线边图形近似重合。

吸附功能应在独立文件中维护，避免把几何计算散落到画布视图中。

---

# 十九、导出系统

## 1. 主要文件

通用导出相关文件包括：

```text
ATeaching/TeachingDocumentExportService.swift
ATeaching/TeachingPrintExportService.swift
ATeaching/TeachingPrintLayoutEngine.swift
ATeaching/TeachingPrintStyleSheet.swift
ATeaching/TeachingPrintRenderingDomain.swift
```

## 2. 导出原则

导出系统要保证：

- App 内看到什么，导出尽量接近什么。
- 深色模式不能破坏固定浅色样式。
- PDF、HTML、图片导出尽量使用同一套样式计算。
- 图片和公式要跟文字使用统一缩放规则。
- 导出路径由系统导出面板决定时，不要额外写入奇怪位置。

---

# 二十、性能维护原则

ATeaching 中最容易卡顿的场景是：

- 大 Markdown 文件删除文字。
- 大 NodeMarkdown 文档删除文字。
- 公式行回车。
- 图片和公式重新渲染。
- 搜索时全量扫描。
- 文档设置改变后全量刷新。

优化原则：

1. 行内改动尽量只处理当前行。
2. 当前行仍存在时，不重算整篇结构。
3. 删除没有跨行时，不触发包保护、H3 保护、母本同步判断。
4. 搜索只在用户确认搜索时执行。
5. 图片和公式缓存尽量复用。
6. 当前正在编辑的行不要被刷新成渲染行。
7. 大文件优先用内存换速度。

---

# 二十一、版本号与记录

版本号规则恢复为：

```text
V1.<日期时间>
```

日期时间使用年月日小时分钟，例如：

```text
V1.2607121530
```

维护时每次重要功能改动应同步：

1. 改版本号。
2. 写入 `Ateaching开发记录.MD`。
3. 必要时更新说明书或白皮书。

---

# 二十二、兼容性要求

这是维护 ATeaching 最重要的一条。

任何改动都必须考虑旧数据：

- 旧学生设置文件可能没有统计页。
- 旧正文层级设置可能只有部分层级。
- 旧机构记录可能没有 ID。
- 旧课记录可能没有完整快照字段。
- 旧 NodeMarkdown 文档可能没有来源信息。
- 旧图片链接可能使用不同相对路径。

读取旧数据时要补默认值，保存时要尽量保留未知字段或至少不破坏可识别内容。

不要因为当前代码需要新字段，就直接重写用户已有文件。

---

# 二十三、测试清单

每次改动后，建议按影响范围做以下检查。

## 1. NodeMarkdown

- 点击任意行能进入编辑。
- 光标进入点击位置。
- 回车后光标进入下一行可输入区。
- 公式行回车不跳到 n+2 行。
- Backspace 合并行后光标位置正确。
- Tab / Shift+Tab 后当前行仍保持源码状态。
- 图片保存后仍能渲染。
- Command+S 后图片和公式不消失。
- Command+Z 后文字不丢显示。
- PDF 和 HTML 导出公式、图片、样式正常。

维护约束：Command+S 保存成功后，不应把当前编辑器内容当作外部文本整篇替换。保存只应把内存 document 写入磁盘，并同步保存状态；除非确实从磁盘重新加载或清理空节点改变了结构，否则不要触发外部文本同步 token，否则图片和公式附件会从渲染态退回源码态。

## 2. 普通 Markdown

- 大文件输入不卡。
- 大文件删除不卡。
- 搜索只在点击搜索或回车后执行。
- 从访达打开不会额外打开主窗口。
- 多个文件进入同一个标签窗口。
- 导出 PDF / HTML / MD 正常。

## 3. 授课

- 进入学生页不创建课反。
- 点击开课才创建上课记录。
- 插入 H3 包后课反内容自动编号。
- 新包入库后随堂笔记回填来源。
- 下课导出 PDF 和 HTML。
- 脏包同步前清理空行。

## 4. 统计

- 机构新增、改名、删除正常。
- 学生统计设置不丢。
- 开课只建立授课会话、当天上课信息和课反，不写入成课JSON。
- 排课转成课遇冲突时不加入。
- 成课和排课右键复制、导出、修改、删除正常。
- 31 号在导出图中完整显示。

## 5. 单列表格

- 模板新增行后旧表保留原内容。
- 模板删除行后旧表对应行消失。
- 导出图片保留圆角和渐变背景。

---

# 二十四、未来线上化建议

如果未来把排课或授课系统线上化，需要提前明确数据策略。

当前用户倾向是：

- 手机端本地文件不明文。
- 服务器端可以看懂数据。
- 未来支持设备之间互相排课。

建议拆分为两层：

1. **本地保护**：移动端本地缓存加密，防止手机丢失后直接读取文件。
2. **服务端协作**：服务端使用可查询数据结构，便于冲突检查、排课同步、权限管理和多人协作。

如果对外宣传“端到端加密”，服务器就不能看懂内容。当前需求并不是端到端加密，应避免使用这个说法。

---

# 二十五、维护禁区

以下位置改动前必须先读代码、理顺流程，不能补丁式乱改：

1. NodeMarkdown 光标定位。
2. NodeMarkdown 公式行回车。
3. NodeMarkdown 新旧管线共用样式。
4. 脏包同步和新包入库。
5. 学生设置页数兼容。
6. 课时记录 JSON 结构。
7. 排课转成课冲突策略。
8. 图片路径生成。
9. PDF / HTML 导出样式。
10. 外部 Markdown 文件窗口管理。
11. H3包同步方向的时间戳比较：`source.mtime > notebook.mtime` 用严格大于；刷新时子行修改必须传播到根H3的mtimeCache，否则方向反判。
12. 公式渲染的 metrics来源必须从SwiftMath typesetter获取真实ascent/descent/axis，禁止从位图宽高猜测；公式字号跟随正文，无硬下限。
13. `applicationShouldHandleReopen` 必须检查 `hasVisibleWindows`，已有可见窗口时不弹主窗口。
14. 排课页面不再锁已完成课程；左键点击弹出操作菜单而非直接编辑；长按在 Mac 和 iPhone 上统一为拖动。
15. 空行的背景条和编号高度必须与有内容时一致：`firstLineRect` 对空行补上 `minimumLineHeight`，不能只用字体自然行高。
16. 公式垂直定位的 `axisHeight` 不能猜：行内公式用 `baseFont.xHeight/2`（对齐x字高），独立公式用字体中线。
17. 投屏功能传输文档 JSON + 层级数据而非视频流；接收端只读，仅提供批注且每学生独有色。
18. 上课期间母本有更新机制暂停：上课中教师不会修改母本，差异全部按随堂→母本处理。

这些位置都有历史 bug，维护时要先找到数据源、状态变化点和刷新入口，再整体改。

---

# 二十六、总结

ATeaching 的复杂度来自它不是一个单点工具，而是一个围绕“真实授课流程”建立的工作系统。

维护时应始终记住三条主线：

1. **上课主线**：学生进入、开课、随堂、下课、同步、导出。
2. **教案主线**：母本、随堂副本、脏包、新包、回写。
3. **统计主线**：学生设置、机构设置、成课记录、排课计划、导出核算。

只要每次改动都明确自己影响哪条主线，并保护其他主线不被误伤，项目就能继续扩展而不失控。

---

# 二十七、统计页面的跨平台布局边界

统计功能共用同一套数据和业务动作，但不能让Mac的横向工具栏和固定窗口尺寸直接进入iPhone。

本轮确立以下布局边界：

1. `TeachingLessonStatisticsSubpageView`只管理统计模式和页面级动作。默认模式统一为排课；紧凑宽度下，模式选择与页面动作分行。
2. `TeachingLessonPlanningBoardView`继续共用排课和周表业务，但紧凑宽度下将月份、导出、学生选择分层。排课网格与记录列表拥有各自的高度和滚动范围，不能用内容固有高度撑大整个授课首页。
3. 学生选择在Mac使用`popover`，在iOS使用系统`sheet`。这是平台交互差异，不复制学生筛选和选中逻辑。
4. 机构列表在常规宽度使用横向统计行，在紧凑宽度使用纵向信息块；两种布局调用同一套右键菜单和机构数据。
5. 编辑器弹页只在Mac设置最小窗口尺寸。iOS由系统决定弹页宽度，内部可能溢出的快捷操作和数据表使用定向滚动。
6. 授课首页主导航在紧凑宽度使用横向滚动，保证按钮点击面积稳定，不允许SwiftUI为塞进一行而把按钮压到不可用。
7. 仅属于macOS的外部Markdown窗口代码，其`AppKit`导入也必须位于`#if os(macOS)`内部；平台判断应覆盖模块导入和实现，而不是只覆盖类型声明。

验收至少包括Mac Debug构建和iPhone Simulator Debug构建。布局运行验收应优先选用较小屏幕设备；如果CoreSimulator本身无法保持启动，需要明确记录运行环境问题，不能把编译成功写成已完成视觉验收。

---

# 二十八、TextKit2首次载入与输入会话边界

Mac的`NSTextView`在进入窗口后可能先成为第一响应者，随后异步磁盘读取才把真实正文送入SwiftUI绑定。输入焦点建立和正文发生修改是两件不同的事，不能共用一个同步阻断条件。

新管线采用以下规则：

1. `isLocalEditingSessionActive`只表达输入会话存在，用于输入状态通知和保存时机。
2. `hasUnacknowledgedLocalText`只表达原生编辑器已经发布了正文，但SwiftUI尚未用相同正文确认该修订。
3. 外部正文与原生存储不同且没有未确认本地正文时，必须接收外部正文；文本框是否有焦点不影响首次载入。
4. 没有未确认本地正文时，行元数据必须与外部正文一起进入协调器，包括Node UUID、层级、Source信息和H3保护状态。
5. 存在未确认本地正文时，迟到的旧外部快照不得整篇覆盖原生存储，继续等待绑定确认。

当前平台边界必须明确：Mac使用`NSTextStorage -> NSTextContentStorage -> NSTextLayoutManager -> NSTextContainer -> NSTextView`的新管线；iOS分支目前仍是SwiftUI `TextEditor`兜底。iPhone能显示正文不等于已经运行新TextKit2管线，后续移动端原生化需要单独实现和验收。

---

# 二十九、旧TextKit管线的Node编辑事务

旧管线的显示缓冲区已经只保存Node Content，不再保存`### `、`- `等层级前缀。因此字符串不具备恢复UUID、level、SourceID和SourceFile的能力，任何以Content重新推断完整Node的实时编辑方案都不可靠。

旧管线采用两层状态：

1. **完整行元数据**：与全部显示行同序，保存每行Node UUID、level、SourceID、SourceFile和H3保护状态，用于12级显示、编号绘制、保护判断和结构操作。
2. **当前编辑Node暂存**：用户进入一行时建立，只保存该UUID对应Node的完整可编辑状态。普通字符事务只更新这里，不重建文档Nodes。

编辑Node暂存以UUID提交，行号只用于当前视图定位，不能作为持久身份。切行和失焦的顺序固定为：读取旧行最终Content、提交旧UUID、更新H3修时和包状态、渲染旧行、建立新行暂存、最后通知父视图活动行变化。

结构事务必须在改变行数组之前提交当前暂存。Enter、跨行删除、行合并、多行层级调整及撤销随后携带完整正文和完整元数据执行，禁止在行数组改变后再用旧行号读取旧Node。

外部元数据只有在UUID完整且不重复时才能覆盖当前完整身份。活动编辑Node的本地暂存优先于迟到的SwiftUI快照。缺失元数据的真正新行使用新UUID并继承邻近层级，不能使用固定第7级占位值。

正文行数与行元数据数量短暂不一致时，解析器不得恢复到“读取正文前缀”的旧逻辑，因为显示正文已经不包含层级前缀。兜底顺序固定为：先按仍可对应原Node的UUID取层级，再按原位置保留层级，最后才让真正超出原文的新行继承邻近层级。任何异常都不得把整篇文档统一写成第7级正文。

父层收到单Node提交后按UUID原位更新文档。若目标在H3包内，调用统一修时与包变化引擎；若目标是H1或H2，则不建立虚假的H3归属。这样显示层级、持久身份和脏包判定使用同一份Node事实。

旧管线的文字行范围由`NodeMarkdownLegacyRowRangeIndex`单独管理。普通字符编辑的输入是原范围、实际编辑行和新正文，输出只能是：当前行按真实换行边界重算，后续行保持长度并连续平移。样式脏行、段间距依赖行和可见区域都不得参与文字坐标计算。每份增量结果必须满足从0开始、逐行首尾相接、不重叠、不越界，并与`NSString.lineRange`逐行相同；否则立即从正文重建。

输入事件顺序固定为：消费原生编辑事务、同步行元数据、更新或重建文字范围、根据新范围确认活动行、设置输入属性、恢复当前行源码显示。marked text组合阶段没有可靠的普通替换回调，因此直接从当前正文重建范围。正文不再包含源码层级前缀后，禁止检测“行首若干字符可能改变层级”。

输入法组合与普通按键是互斥事务。检测到marked text后必须立即废弃此前可能登记的普通字符替换，组合期间每次按当前存储重建范围；从拼音确认成中文的第一次非marked回调也必须重建，不能使用组合开始时第一个字母留下的字符差。没有`PendingEdit`的文字回调只影响当前活动行，不得默认扩大到相邻行。
