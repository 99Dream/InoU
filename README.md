# InoU

**InoU** 是一款本地优先、BYOK（自备 API Key）的 **AI 拍照录题、错题整理、A4 数字稿纸练习与智能伴学**跨端应用（Flutter Monorepo）。

拍下试卷或练习册后，AI 自动完成切题与结构化校对入库，沉淀个人题库与错题本；支持「标准数字化作答」与「A4 手写稿纸」双模式练习、知识点薄弱诊断，以及看板娘 **诺诺** 的分步互动讲解与 **AI 黑板讲堂**。

---

## 核心特性

- **多模态录题与分屏校对**
  - 支持相机拍照、相册选图、文档导入与纯文本粘贴录题，支持原卷与答案双图对齐。
  - 提供原图 / 结构化题块联动分屏校对（[review](apps/inou_app/lib/features/review)），含去重检测（SimHash）与题目规范校验。
- **全题型题库与错题闭环**
  - 统一题目协议与判分引擎（[inou_domain](packages/inou_domain)），覆盖选择、多选、填空、连词/排序、连线、分类、解答、画图、复合题组等题型。
  - 错题自动沉淀至错题本，按知识点树统计薄弱项，支持掌握度连续打卡（`N` 次答对毕业）与 AI 针对性变式题生成。
- **双模式做题体验与低延迟墨水引擎**
  - **标准作答**：面向手机与触屏的高效交互作答界面，支持公式/文本与图片附件交卷。
  - **A4 手写稿纸**：内置自研墨水引擎（[inou_ink](packages/inou_ink)），支持低延迟笔迹绘制、防误触、底纹切换、可扩展解题空间及圈选笔迹区域导出截图向 AI 提问。
- **诺诺伴学助手 & AI 黑板讲堂**
  - **自主 Agent 工具链**（[inou_ai](packages/inou_ai)）：基于 `dart_agent_core` 构建，支持思考、数学表达式验算与引导式讲题；严格遵守学习主题边界与分层防剧透策略（L1 思路点拨 / L2 关键步骤 / L3 详细解答）。
  - **AI 黑板讲堂**（[tutor](apps/inou_app/lib/features/tutor)）：支持流式分步板书、静态/几何示意图渲染、左侧可折叠原题栏、双向互动小测与反馈重规划、圈选黑板提问及笔记一键收入错题本。
- **多协议 AI 网关（BYOK）与本地数据安全**
  - 原生支持 **Google Gemini** 与 **OpenAI 兼容格式**（可接 OpenAI、通义千问 VL、智谱、豆包、One-API / New-API 等兼容端点），支持分档模型（Fast / Balanced / Strong）配置与连通性测试。
  - 本地加密与家长密码保护、`.inou` 压缩备份归档（含 SHA-256 完整性校验与一键导入导出）。
- **手机/平板自适应与异形屏适配**
  - 统一自适应设计系统（[inou_ui_kit](packages/inou_ui_kit)），手机端与平板双栏工作台自动切换；在 Android 原生层（`WindowInsetsCompat.Type.displayCutout()`）与 Flutter 层联合解析挖孔屏/刘海屏安全区，确保横屏与自动旋转黑板不被遮挡。
- **完整运行时诊断日志**
  - 内置环形缓冲日志器 `InouDiagnosticsLogger`，捕获 UI、异步与 AI/原生通道完整报错堆栈，自动对 API Key、`Bearer` 凭据与 Token 进行脱敏，并在「设置 → 安全与备份」支持无截断查看及 `.txt` 导出/分享/复制。

---

## 工程结构

项目采用 Dart Pub Workspace + Melos Monorepo 架构：

```text
InoU/
├── pubspec.yaml                     # Workspace 与 Melos 脚本配置
├── analysis_options_shared.yaml     # 全局共享 Lint 规则
├── apps/
│   └── inou_app/                    # 主 Flutter 应用（Android / iOS / Desktop）
│       ├── android/                 # Android 原生工程与 MethodChannel（相机、文件导出、DisplayCutout）
│       ├── assets/                  # 知识点树种子 JSON、Prompt 模板（P-01..P-18）、诺诺资源
│       └── lib/features/            # 业务模块：home, capture, review, library, practice, wrongbook, analytics, tutor, settings, onboarding
├── packages/
│   ├── inou_domain/                 # 纯 Dart 领域层：题型协议、校验器、判分引擎、掌握度/薄弱点分析、诊断日志
│   ├── inou_ai/                     # AI 网关与 Agent 服务：Gemini/OpenAI 适配、P-01..P-18 模板渲染、流式板书与辅导代理
│   ├── inou_ink/                    # 手写墨水引擎：笔迹模型、画布渲染、防误触与区域导出
│   └── inou_ui_kit/                 # 设计系统：明暗主题 Token、自适应断点、图表与诺诺组件
├── docs/                            # 产品与研发文档、低保真原型
└── tool/
    └── build_kp_tree.dart           # 从文档生成 assets/knowledge/kp_tree_v1.json 的工具脚本
```

---

## 技术栈与环境要求

- **Dart SDK**: `^3.14.0`
- **Flutter**: `>=3.29.0`
- **状态管理与路由**: `flutter_riverpod`、`go_router`
- **AI 与网络**: `dart_agent_core`、`dio`、`mustache_template`
- **本地存储与归档**: `archive`、`crypto`
- **工作区管理**: `melos`

---

## 快速开始

### 1. 安装依赖

在仓库根目录执行：

```bash
flutter pub get
```

如使用 Melos：

```bash
dart run melos bootstrap
```

### 2. 运行应用

```bash
cd apps/inou_app
flutter run
```

> 应用数据默认完全保存在本地。首次运行完成引导后，可在右上角「**设置**」中配置你的 Gemini 或 OpenAI 兼容端点与 API Key（不配置 Key 时仍可离线体验本地题库与基础功能）。

### 3. 常用开发与验证命令

- **静态代码检查**：
  ```bash
  flutter analyze packages/inou_domain packages/inou_ai apps/inou_app
  ```
- **运行纯 Dart 单元测试**（领域模型与 AI 服务）：
  ```bash
  dart test packages/inou_domain/test/domain_engine_test.dart packages/inou_ai/test/agent_services_test.dart
  ```
- **运行 Flutter Widget 与端到端测试**：
  ```bash
  cd apps/inou_app
  flutter test
  ```
- **重新生成知识点树资源**：
  ```bash
  dart run tool/build_kp_tree.dart
  ```
- **构建 Android 正式版 APK**：
  ```bash
  cd apps/inou_app
  flutter build apk --release
  ```
  构建产物输出至 `apps/inou_app/build/app/outputs/flutter-apk/app-release.apk`。

---

## 相关文档

- [产品需求文档 PRD](docs/01-需求文档-PRD.md)
- [系统开发文档](docs/02-开发文档.md)
- [低保真线框图](docs/03-低保真线框图.md)
- [题型 JSON 示例与 AI Prompt 模板库](docs/04-题型JSON示例与AI-Prompt模板库.md)
- [知识点树种子](docs/05-知识点树种子.md)
- [交互原型说明](docs/prototype/README.md)
