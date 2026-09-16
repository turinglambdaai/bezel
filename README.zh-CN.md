# Bezel

用 [Racket](https://racket-lang.org/) 写原生 [Qt 6](https://www.qt.io/) 桌面应用——真正的原生控件，三平台一致。补上 Racket 桌面开发缺失的一块。

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.1.0-C15F3C)](CHANGELOG.md)

[English](README.md) · **中文**

<p align="center"><img src="docs/showcase.png" alt="Bezel Showcase —— Racket 写就的真 Qt 界面" width="720"></p>

## 为什么选择 Bezel？

Racket 自带的 `racket/gui` 可以用，但很难做出产品级的界面样式；Glaze 的 Web 方案拿原生控件换了 HTML。Bezel 走第三条路：按成熟语言的做法绑定业界标准的控件工具箱——C++ shim 暴露稳定 C ABI、信号桥、所有权注册表、spec 驱动的生成器（即 PySide/Shiboken 与 PyQt/SIP 的架构，搬到 Racket）。

你将获得：

- **真原生控件** —— QMainWindow、按钮、输入框、列表、滑条、菜单、对话框，三平台原生观感
- **QSS 样式** —— 用 Qt 的 CSS 方言给任何控件做样式（`QPushButton { background: #C15F3C; border-radius: 8px; }`）
- **真正能用的线程模型** —— 任意 Racket 线程调用任意控件；信号处理器就是普通的 Racket 过程
- **Agent 友好的验证** —— `widget-grab-png` 把任意控件渲染成 PNG；整套测试以 `QT_QPA_PLATFORM=offscreen` 在 CI 无头运行

### Hello Bezel

```racket
#lang racket/base
(require bezel)

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
| 控件丰富度 | 全套 Qt 控件 | 基础集合 | 不限（Web） |
| 样式 | **QSS（CSS 方言）** | 有限 | 完整 CSS |
| 线程 | **任意 Racket 线程** | 绑定 eventspace | 任意线程 |
| 原生工具链 | C++ 编译器 + Qt 6（或预编译 shim） | 无 | 无 |
| 二进制体积 | 小（系统 Qt） | 小 | 小 |

诚实差距：shim 需要一次性原生构建（预编译二进制在路线图上）；类型化信号表目前覆盖首参为 `bool`/`int`/`QString` 的信号，其他信号类型以无参形式送达；v0.1 覆盖核心控件集，尚非全部 Qt。

## 工作原理

四块组件，对应成熟绑定家族（Shiboken、SIP、Qtah）的共同骨架：

1. **C++ shim，C ABI**（`bezel-shim/`）—— Racket FFI 说 C，Qt 说 C++，因此用约 90 个扁平 C 函数把 Qt 类包装在不透明句柄之后（`bezel.h` 即全部契约）
2. **协作式编组** —— Qt 要求 GUI 线程；而 Racket CS 协作式调度线程，一次裸的外国阻塞调用可能冻住所有线程。Bezel 的 C 侧从不在跨线程交接处阻塞：Racket 层入队、在 Racket 信号量上等待、由泵排水
3. **信号桥** —— Qt 信号 → C++ sink 对象 → 加锁队列 → Racket 调度线程 → 你的过程；处理器里的 Qt 调用自动编组回 GUI 线程
4. **所有权注册表** —— 遵循 Qt 父子规则，无父对象由 Racket finalizer 清理；失效句柄可检测（`bezel-alive?`）、绝不崩溃

深入设计见 [docs/architecture.md](docs/architecture.md)。

## 平台支持状态

| 能力 | macOS | Windows | Linux |
|---|---|---|---|
| Application / 运行循环（泵） | ✅ | ✅ | ✅ |
| 核心控件（13）+ 布局（4） | ✅ | ✅ | ✅ |
| 菜单 + 动作 | ✅ | ✅ | ✅ |
| 信号（类型化：bool / int / double / QString） | ✅ | ✅ | ✅ |
| 跨线程控件访问 | ✅ | ✅ | ✅ |
| QSS 样式 | ✅ | ✅ | ✅ |
| `widget-grab-png`（截图） | ✅ | ✅ | ✅ |
| 无头 CI（offscreen e2e） | ✅ | ✅ | ✅ |

三个平台在 CI 里跑同一套真对象 e2e——23 个测试覆盖控件、布局、类型化信号投递、泵循环与 PNG 渲染。

## 环境要求

| 依赖 | 用途 |
|------|------|
| [Racket](https://racket-lang.org/) | 8.0 或更高（含 `raco`） |
| Qt 6 + CMake + C++17 编译器 | 构建 `libbezel`（一条命令；预编译二进制在路线图上） |

## 快速开始

### 1. 构建 shim

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
```

若构建产物不在系统路径上，用 `$BEZEL_LIBRARY` 指向该库。macOS 用 Homebrew 的 Qt（`brew install qt`），Linux 用发行版的 `qt6-base-dev`。

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

`run` 是泵循环，不是阻塞 exec——这正是信号处理器与跨线程调用能存活的原因（见架构文档）。关闭最后一个可见窗口同样会让泵停止（即泵循环版的 quit-on-last-window-closed）；`(widget-close! win)` 可编程关闭，`set-quit-on-last-window-closed!` 可开关该行为。

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
(connect! btn "clicked()" (lambda _ (displayln "clicked!")))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

信号使用 Qt 规范化签名。处理器运行在 Bezel 的调度线程上，可以随意混写 Racket 计算与控件调用（自动编组回 GUI 线程）。

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
(emit-test-signal! btn "clicked()")      ; 测试中驱动完整信号桥
```

README 的 showcase 图本身由 `scripts/showcase.rkt` 生成——无头环境产出的真 Qt 渲染。

### 对象模型

```racket
(bezel-alive? widget)          ; Qt 是否已销毁？
(bezel-delete! widget)         ; 显式 deleteLater
(object-name widget)           ; 命名、重挂父级、GC 安全句柄
```

所有权遵循 Qt 父子规则：带父创建 → Qt 持有；无父 → Bezel 统一跟踪，应用退出时全部回收（需要提前回收用 `bezel-delete!`）。`layout!` 自动把所有权移交 Qt。这里刻意不做 GC 驱动的删除——迟到的 finalizer 删掉被复用地址上的无辜控件，正是 Bezel 拒绝接受的一类竞态。

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
└── docs/             # architecture.md 深入设计
```

## 添加 Qt 类（生成器）

覆盖度的扩张方式与 Shiboken/SIP 一致——spec 驱动。写一份 JSON spec 描述构造器与方法，然后：

```bash
racket tools/generator/generate.rkt tools/generator/specs/dial.json
```

同时产出 shim 侧（`src/generated/dial_gen.cpp`）与 Racket 侧（`bezel-lib/generated/dial_gen.rkt`）——重新构建，新类即端到端可用。`QDial` 是随库附带的完整示例。

## 测试

```bash
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

真 Qt 对象、真信号投递、真 PNG 渲染——在每个 OS 上无头运行。CI（`.github/workflows/ci.yml`）在 ubuntu/windows/macos 上以 Qt 6 构建 shim 并跑同一套测试，随后重新生成 showcase 截图作为产物。

## 路线图

- [x] **Phase 1** —— C++ shim + C ABI、控件、布局、菜单、对话框
- [x] **Phase 2** —— 带类型参数的信号桥、协作式线程模型、所有权注册表、生成器管线
- [x] **Phase 3** —— 三平台无头 e2e、PNG 验证、showcase 生成
- [ ] **Phase 4** —— 各平台预编译 shim 二进制（装完即用，无需工具链）
- [ ] **Phase 5** —— 以 spec 扩大控件覆盖；`bezel/class`（send 风格 API）；应用打包发布方案

## 许可证

基于 [MIT 许可证](LICENSE) 授权。
