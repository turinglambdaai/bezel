# Bezel

用 [Racket](https://racket-lang.org/) 写原生 [Qt 6](https://www.qt.io/) 桌面应用——真正的原生控件，三平台一致。补上 Racket 桌面开发缺失的一块。

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.1.0-C15F3C)](CHANGELOG.md)

[English](README.md) · **中文**

<p align="center"><img src="docs/showcase.png" alt="Bezel Showcase —— Racket 写就的真 Qt 界面" width="720"></p>

## 为什么选择 Bezel？

Racket 自带的 `racket/gui` 可以用，但很难做出产品级的界面样式；Glaze 的 Web 方案则用 HTML 换取灵活性。Bezel 走第三条路：绑定成熟的 Qt Widgets——C++ shim 暴露稳定 C ABI，Racket 层负责协作式 GUI 线程编组、信号桥、显式生命周期规则，并通过 spec 驱动的生成器逐步扩大 Qt 覆盖面。

你将获得：

- **真 Qt 控件** —— QMainWindow、按钮、输入框、列表、滑条、菜单、对话框，并可通过生成器继续扩展
- **QSS 样式** —— 用 Qt 的 CSS 方言给控件做样式（`QPushButton { background: #C15F3C; border-radius: 8px; }`）
- **明确的线程模型** —— Bezel 的公开控件 API 可从任意 Racket 线程调用；信号处理器就是普通 Racket 过程
- **Agent 友好的验证** —— `widget-grab-png` 可把控件渲染为 PNG；整套测试以 `QT_QPA_PLATFORM=offscreen` 在 CI 无头运行
- **受检查的 native 边界** —— Racket 包加载时会验证 shim ABI，避免绑定与本地库错配后才在运行时随机失败

### Hello Bezel

```racket
#lang racket/base
(require bezel)

(make-application #:name "Hello Bezel")

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))
(connect! btn "clicked()" (lambda _
  (set-box! n (add1 (unbox n)))
  (widget-set-text! count (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox count btn))
(run win)
```

### 横向对比

| | Bezel (Qt 6) | racket/gui | Glaze (Web UI) |
|---|---|---|---|
| 工具箱 | Qt 6 Widgets | wx 原生封装 | HTML/CSS/JS |
| 控件丰富度 | 当前为核心集合；生成器持续扩展 | 基础集合 | 不限（Web） |
| 样式 | **QSS（CSS 方言）** | 有限 | 完整 CSS |
| 线程 | **公开 API 可从任意 Racket 线程调用** | 绑定 eventspace | 任意线程 |
| 原生工具链 | 当前需要 | 无 | 无 |
| 二进制体积 | 使用系统 Qt 时较小 | 小 | 小 |

当前差距明确写在这里：公开版本还没有提供经过验证的便携预编译 shim/Qt 运行时发布包；v0.1 覆盖核心控件集，而不是全部 Qt。类型化信号参数目前支持 `bool`、`int`、`double`、`QString`，暂不支持的参数类型会以不带转换参数的方式投递。

## 工作原理

四块组件，对应成熟绑定家族（如 Shiboken、SIP）的共同骨架：

1. **C++ shim，C ABI**（`bezel-shim/`）—— Racket FFI 说 C，Qt 说 C++，因此通过扁平 C 函数把 Qt 类包装在经过校验的不透明句柄之后（`bezel.h` 是 native 边界契约）
2. **协作式编组** —— Qt 要求 GUI 线程；而 Racket CS 协作式调度线程，一次裸的 foreign 阻塞等待可能卡住整个调度器。Bezel 的 C 侧不做阻塞式跨线程交接：Racket 层把任务入队，在 Racket 信号量上等待，由 GUI 泵执行
3. **信号桥** —— Qt 信号 → C++ sink → 加锁队列 → Racket 调度线程 → 用户过程；处理器里的 Bezel 控件调用自动编组回 GUI 线程
4. **生命周期注册表** —— 遵循 Qt 父子所有权，同时维护 `QObject` 活句柄注册表。无父对象保持存活直到显式删除或 application teardown；Bezel 刻意不使用会删除对象的 GC finalizer，失效句柄会被拒绝而不是解引用

深入设计见 [docs/architecture.md](docs/architecture.md)。

## 平台支持状态

| 能力 | macOS | Windows | Linux |
|---|---|---|---|
| Application / 运行循环（泵） | ✅ | ✅ | ✅ |
| 核心控件 + 布局 | ✅ | ✅ | ✅ |
| 菜单 + 动作 | ✅ | ✅ | ✅ |
| 信号（类型化：bool / int / double / QString） | ✅ | ✅ | ✅ |
| 跨线程控件访问 | ✅ | ✅ | ✅ |
| 生成绑定的跨线程编组 | ✅ | ✅ | ✅ |
| QSS 样式 | ✅ | ✅ | ✅ |
| `widget-grab-png`（截图） | ✅ | ✅ | ✅ |
| 无头 CI（offscreen e2e） | ✅ | ✅ | ✅ |

三个平台在 CI 里跑同一套真对象端到端测试，覆盖控件、布局、类型化信号投递、跨线程访问、泵循环、生命周期/错误路径与 PNG 渲染。CI 还会重新运行绑定生成器，并拒绝未同步提交的生成产物。

## 环境要求

| 依赖 | 用途 |
|------|------|
| [Racket](https://racket-lang.org/) | 8.0 或更高（含 `raco`） |
| Qt 6 + CMake + C++17 编译器 | 当前用于构建 `libbezel` |

## 快速开始

### 1. 构建 shim

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
```

若构建产物不在系统路径上，用 `$BEZEL_LIBRARY` 指向该库。macOS 可用 Homebrew 的 Qt（`brew install qt`）；Linux 安装发行版提供的 Qt 6 开发包。

### 2. 安装包

```bash
raco pkg install --auto --link ./bezel-lib ./bezel
```

### 3. 运行

```bash
racket examples/hello.rkt
```

会打开一个真 Qt 窗口。`examples/counter.rkt` 演示 QSS 样式；`examples/form.rkt` 演示表单布局、菜单与对话框。

> 想参与 Bezel 开发？`raco pkg install --auto --no-docs --link ./bezel-lib ./bezel ./bezel-test`，然后 `raco test bezel-test/`。

## API 速览

### 应用生命周期

```racket
(make-application #:name "My App")  ; 幂等；创建控件前必须先调用
(run win)                           ; 显示 win，泵循环直到退出
(quit! 0)                           ; run 返回 0
```

`run` 是泵循环，不是阻塞 exec——这正是信号处理器与跨线程调用能继续运行的原因。关闭最后一个可见窗口同样会让泵停止；`(widget-close! win)` 可编程关闭，`set-quit-on-last-window-closed!` 可切换该行为。

### 控件与布局

```racket
(define win (make-window #:title "Team" #:size '(420 240) #:stylesheet qss))
(define name (make-line-edit)) (set-placeholder! name "Ada Lovelace")
(define experience (make-slider)) (set-widget-range! experience 0 15)

(layout! win
         (vbox #:margins '(20 20 20 20)
               (form (list "Name:" name)
                     (list "Experience:" experience))
               (hbox stretch (make-button "Submit"))))
```

树形写法负责组合（`vbox` / `hbox` / `grid` / `form` / `stretch`），需要时也可用命令式构造（`make-vbox`、`layout-add!`、`grid-put!`）。

### 信号

```racket
(define conn-id
  (connect! btn "clicked()" (lambda _ (displayln "clicked!"))))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

信号使用 Qt 规范化签名。处理器运行在 Bezel 的调度线程上，可以混写 Racket 计算与公开控件调用，后者会自动编组回 GUI 线程。显式断连、目标对象销毁和应用清理都会回收对应的 native 连接记录与 Racket handler。

### 菜单与对话框

```racket
(define file (menu! (menu-bar win) "File"))
(connect! (menu-action! file "Quit") "triggered()" (lambda _ (quit!)))
(msg-question "Delete 3 items?" #:parent win)   ; #t / #f
```

### 验证（Agent 友好）

```racket
(define png (widget-grab-png win))       ; 任意控件渲染为真 PNG 字节
(process-events! 50)                     ; 非阻塞泵
(emit-test-signal! btn "clicked()")      ; 测试中驱动信号桥
```

README 的 showcase 图本身由 `scripts/showcase.rkt` 生成——无头环境产出的真 Qt 渲染。

### 对象模型

```racket
(bezel-alive? widget)                 ; Qt 对象是否仍存活？
(bezel-delete! widget)                ; 显式 deleteLater
(qt-object-name widget)               ; QObject 名称
(set-qt-object-name! widget "x")
(object-set-parent! widget parent)
```

所有权遵循 Qt 父子规则：带父创建 → Qt 持有；无父对象则保持存活，直到显式删除或 application teardown。`layout!` 会自动把所有权移交 Qt。这里刻意不做 GC 驱动删除——迟到的 finalizer 删除已经复用地址上的另一个控件，正是 Bezel 要避免的竞态。

## 仓库结构

```
bezel/
├── bezel/            # Umbrella 包（安装 `bezel` 即包含全部）
├── bezel-lib/        # Racket FFI 绑定（collection `bezel`）
├── bezel-shim/       # C++ shim：Qt 6 之上的 C ABI（CMake）
├── bezel-doc/        # 文档（Scribble）
├── bezel-test/       # 测试（无头 e2e，三平台运行）
├── examples/         # hello / counter / form
├── tools/generator/  # JSON class spec → C++ + Racket 绑定
└── docs/             # 架构与设计说明
```

## 添加 Qt 类（生成器）

覆盖度采用 spec 驱动扩展。写一份 JSON spec 描述构造器与方法，然后：

```bash
racket tools/generator/generate.rkt tools/generator/specs/dial.json
```

会同时产出 shim 侧（`bezel-shim/src/generated/dial_gen.cpp`）与 Racket 侧（`bezel-lib/generated/dial_gen.rkt`）。生成的公开 API 与手写绑定遵循同样的对象存活检查、错误传播和 GUI 线程编组规则；`QDial` 是随库附带的完整示例，CI 会拒绝过期的生成文件。

## 测试

```bash
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

真 Qt 对象、真信号投递、真 PNG 渲染——在每个 OS 上无头运行。CI（`.github/workflows/ci.yml`）在 Ubuntu、Windows、macOS 上用 Qt 6 构建 shim 并运行同一套测试，同时检查生成产物、构建文档并产出 showcase artifact。

## 生产 / 分发状态

核心运行时已经有三平台测试，但分发链路目前仍然明确标记为未完成：仓库现在没有 GitHub Release 提供经过干净机器验证的便携预编译 shim 与 Qt 运行时部署包。因此当前更准确的状态是 **源码构建可用**，还不是 **零工具链安装可用**。

## 路线图

- [x] **Phase 1** —— C++ shim + C ABI、控件、布局、菜单、对话框
- [x] **Phase 2** —— 带类型参数的信号桥、协作式线程模型、生命周期注册表、生成器管线
- [x] **Phase 3** —— 三平台无头 e2e、PNG 验证、showcase 生成
- [x] **Phase 3.5** —— ABI 校验、生命周期加固、生成绑定线程安全、生成产物一致性 CI
- [ ] **Phase 4** —— 各平台便携预编译 shim/运行时产物（无需编译器即可安装）
- [ ] **Phase 5** —— 以 spec 扩大控件覆盖；`bezel/class`（send 风格 API）；应用打包发布方案

## 许可证

基于 [MIT 许可证](LICENSE) 授权。
