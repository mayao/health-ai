# 首页偶数布局与数据页排版优化

## Summary
本轮只做 iOS 端首页/数据页体验优化，不改后端接口语义。目标是把首页的核心指标与趋势板改成“高频优先、无数据自动隐藏、默认显示偶数张”，并把首页底部改成两个独立分析模块；同时重排数据页“添加数据”卡片，移除常驻失败提示。

## Key Changes

### 1. 首页核心指标与趋势板改成“偶数优先 + 高频优先”
在 [HomeScreen.swift](/Users/xmly/Projects/MyCodex/Health/ios/VitalCommandIOS/Features/Home/HomeScreen.swift) 抽出两套纯 helper：`visiblePulseCards` / `visibleTrendBoards`，统一处理排序、隐藏、折叠和展开状态，避免直接 `ForEach` 固定候选数组。

卡片优先级按高频优先固定为：
1. 运动时间
2. 步数
3. 睡眠
4. 体重
5. 体脂
6. 饮食热量
7. 血脂/LDL-C
8. 低频遗传/慢变量卡片（如 Lp(a) 背景）

展示规则固定为：
- 无数据卡片直接隐藏，不占位。
- 可展示卡片数为 `0`：整块隐藏，改显示该 section 的空态引导。
- 可展示卡片数为 `1`：显示 1 张全宽卡，不强行凑偶数。
- 可展示卡片数为 `2/4/6...`：全部显示。
- 可展示卡片数为 `3/5/7...`：默认显示前 `2/4/6...` 张，最后 1 张收进“展开更多”。
- 展开后显示全部卡片；收起后恢复偶数张。
- “展开更多”只在存在被折叠项时出现，且放在 section 底部，不占据卡片位。

趋势板与核心指标都使用同一套规则，但趋势板的优先顺序按图表维度落位：
1. activity
2. recovery
3. bodyComposition
4. diet
5. lipid

### 2. 首页底部改为两个独立分析模块，替换“数据拼图”
移除首页当前 `sourceDimensionsSection` 的展示，不再在首页底部放横向“数据拼图”芯片区。

新增两个独立 SectionCard：
- `运动与睡眠分析`
  - 优先消费现有 `dimensionAnalyses` 里的 `activity_recovery`
  - 有数据时展示：标题、1 段摘要、2-3 条 goodSignals / needsAttention / actionPlan 的精简版
  - 无数据时展示引导空态：主文案 + “去同步 Apple 健康” CTA，跳转数据页或设置里的 Apple 健康同步入口
- `饮食健康分析`
  - 消费现有 `dimensionAnalyses` 里的 `diet`
  - 有数据时展示：摘要、记录覆盖、热量趋势、建议动作
  - 无数据时展示引导空态：主文案 + “去上传饮食数据” CTA，跳转数据页饮食上传入口

展示规则固定为：
- 这两个模块始终位于首页底部。
- 有分析数据时展示分析版；无分析数据时展示引导版。
- 不再额外保留首页底部的 source dimension 芯片入口；覆盖维度保留在数据页查看。

### 3. 首页空态与模块显隐统一
首页 section 级显隐改成更一致的规则：
- `核心指标`、`趋势板`：按卡片 helper 的结果决定显示、空态或折叠。
- `身体组成`、`基因健康维度`、`最近报告` 等继续沿用“有数据才显示”的原则。
- 运动/睡眠分析和饮食分析不隐藏 section，本轮改为空态引导承接无数据情况。

空态文案固定方向：
- 运动睡眠无数据：强调同步 Apple 健康。
- 饮食无数据：强调上传饮食照片。
- 不再出现“模块标题在，但里面空白”的状态。

### 4. 数据页“添加数据”卡片重排
在 [DataHubScreen.swift](/Users/xmly/Projects/MyCodex/Health/ios/VitalCommandIOS/Features/DataHub/DataHubScreen.swift) 调整 `DataTypeCard` 布局：
- icon 独立在第一行居中或左上，不与标题同行。
- 标题单独一行。
- 说明文案单独一行/多行完整展示，不截断关键信息。
- 卡片高度对齐，保证两列网格视觉整齐。
- 选中态保留，但 check icon 不再挤压正文。

实现方向固定为：
- 卡片主体从当前 `HStack` 改成 `VStack`。
- `description` 取消 3 行截断，改为完整换行显示；必要时给卡片最小高度，避免两列高差过大。
- “添加数据”上层标题副标题文案保留，但不要再让正文说明依赖 hover/展开才可见。

### 5. “处理失败”提示改为短暂反馈，不常驻页面
在 [DataHubViewModel.swift](/Users/xmly/Projects/MyCodex/Health/ios/VitalCommandIOS/Features/DataHub/DataHubViewModel.swift) 和数据页视图中，把 `importPhase == .failed` 从常驻卡改为短暂态。

交互固定为：
- 上传失败时显示失败反馈卡或顶部 banner。
- 约 4 秒后自动收起，页面恢复正常布局。
- 失败详情继续保留在“最近任务”或 `latestPrivacyMessage` 里，避免信息丢失。
- 新的上传开始时，旧失败提示立即清空。
- 成功态仍可短暂显示完成反馈，但不要求长期驻留。

## Public APIs / Interfaces / Types
- 服务端 API、移动端网络模型、`HealthHomePageData` 结构本轮不改。
- 仅新增 iOS 本地 UI helper / state：
  - 首页卡片可见性与折叠状态 helper
  - 首页两个底部分析 section 的本地 view model/adapter
  - 数据页失败提示的自动收起状态

## Test Plan
- 首页核心指标：
  - 3 张有数据时默认显示 2 张 + “展开更多”
  - 5 张有数据时默认显示 4 张 + “展开更多”
  - 1 张有数据时显示 1 张全宽卡
  - 无数据时 section 隐藏并显示对应引导
- 首页趋势板：
  - 高频图表优先于低频图表
  - 无数据图表不占位
  - 展开/收起后卡片数与顺序稳定
- 首页底部：
  - `activity_recovery` 有数据时显示运动睡眠分析内容
  - `diet` 有数据时显示饮食健康分析内容
  - 两者无数据时分别显示 Apple 健康同步 / 饮食上传引导
  - 原“数据拼图”不再出现在首页
- 数据页添加数据：
  - icon、标题、说明分层展示
  - 说明文案可完整换行，不被截断
  - 选中态不挤压正文
- 失败反馈：
  - 上传失败后提示出现
  - 约 4 秒后自动消失
  - 页面重新进入、再次上传、切换类型时不会残留旧失败提示
  - 最近任务仍能看到失败结果

## Assumptions
- 这次优化只动 iOS 客户端展示层，不新增后端字段。
- 首页“偶数美观”规则仅用于卡片网格；当只有 1 个有效卡片时，允许以全宽单卡作为特例。
- “运动与睡眠分析”使用现有 `activity_recovery` 分析结果，“饮食健康分析”使用现有 `diet` 分析结果，不新增新的分析维度。
- 首页移除“数据拼图”后，数据覆盖与来源信息仍保留在数据页查看，不再要求首页承担该入口。
