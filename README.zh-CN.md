# Bezel

用 [Racket](https://racket-lang.org/) 写原生 [Qt 6](https://www.qt.io/) 桌面应用。在 Windows、macOS、Linux 上使用真正的 Qt Widgets，同时保留 Racket 的开发体验。

[![CI](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/bezel/actions/workflows/ci.yml) ![Racket](https://img.shields.io/badge/Racket-9F1D20?logo=racket&logoColor=white) ![Qt6](https://img.shields.io/badge/Qt_6-41CD52?logo=qt&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE) [![Release](https://img.shields.io/badge/release-0.2.0-C15F3C)](CHANGELOG.md)

[English](README.md) · **中文**

## 为什么选择 Bezel？

Racket 自带的 `racket/gui` 可以完成桌面开发，但要做现代、统一、产品级的视觉体验并不轻松；Web 壳方案拥有 CSS，却不再是真正的原生控件。Bezel 选择第三条路：在 Qt Widgets 上建立稳定 C ABI，再由 Racket 层负责 GUI 线程编组、信号桥、生命周期、诊断与绑定生成。

你将得到：

- **真 Qt 控件** —— 窗口、按钮、输入框、列表、滑条、菜单、对话框、布局，并通过生成器继续扩展。
- **QSS 样式** —— 使用 Qt 的 CSS 风格系统构建商业界面。
- **明确的线程语义** —— 公开控件 API 可以从任意 Racket 线程发起，自动编组到 GUI 线程。
- **Agent 友好的验证能力** —— `widget-grab-png` 可渲染真实控件；CI 使用 Qt offscreen 后端做无头真对象测试。
- **受检查的 native 边界** —— 加载时验证 shim ABI，尽早发现 Racket 绑定与 native 库版本不匹配。
- **便携发行包** —— 支持的平台会把 `libbezel`、Qt runtime、Qt plugins 以及强制要求的许可证/重链接材料一起打进 Racket 包；最终用户不需要 Qt SDK、CMake 或 C++ 编译器。
- **运行环境诊断** —— `raco bezel doctor` 会报告平台、架构、native 搜索路径、环境变量和 ABI 加载状态。
- **默认拒绝不合规发布** —— 公共二进制统一从 QtBase 6.8.4 公共源码和截至 2026-09-22 已审查的 Qt 6.8 官方安全补丁构建，采用 LGPLv3 动态链接，并由 CI 强制检查对应源码、许可证与依赖边界。

<p align="center"><img src="docs/showcase.png" alt="Bezel Showcase —— Racket 写就的真 Qt 界面" width="720"></p>

## Hello Bezel

```racket
#lang racket/base
(require bezel)

(make-application #:name "Hello Bezel")

(define n (box 0))
(define count (make-label "Clicked 0 times"))
(define btn (make-button "Click me"))

(connect! btn "clicked()"
          (lambda _
            (set-box! n (add1 (unbox n)))
            (widget-set-text! count
                              (format "Clicked ~a times" (unbox n)))))

(define win (make-window #:title "Hello Bezel" #:size '(320 140)))
(layout! win (vbox count btn))
(run win)
```

## 安装发布版

普通应用开发者在受支持的平台上只需要 **Racket 8.0+**。从 GitHub Release 下载对应的 `bezel-lib-<platform>.zip`，然后把它作为 `bezel-lib` 包安装：

```text
raco pkg install --auto --name bezel-lib /path/to/bezel-lib-<platform>.zip
raco bezel doctor
```

当前预编译目标：

| 平台 | 发布包 | 用户需要 Qt SDK/CMake/编译器吗？ |
| --- | --- | --- |
| Linux x86_64 | `bezel-lib-linux-x86_64.zip` | 不需要 |
| Windows x86_64 | `bezel-lib-windows-x86_64.zip` | 不需要 |
| macOS Apple Silicon | `bezel-lib-macosx-aarch64.zip` | 不需要 |

每个发布包都会经历一次**真正的干净机器验证**：第二台 CI runner 只安装 Racket，不安装 Qt 开发环境、CMake 或 C++ 编译器；然后通过 `raco pkg install` 安装 zip，运行 `raco bezel doctor`，创建真实 Qt 控件、泵事件并执行清理。这个测试不会设置 `BEZEL_NATIVE_DIR`，因此验证的就是用户真正使用的 package-local runtime 路径。

Release 同时发布原始 `bezel-native-*` runtime archive、自包含 Racket 包对应的 `.CHECKSUM`、统一 `SHA256SUMS`、Qt 再分发记录，以及**与公共 runtime 策略对应的、经过 SHA-256 校验的 QtBase 基础源码与官方安全补丁包**。每个 native runtime 自身还包含 `LICENSES/`，其中有 Bezel MIT License、Qt License 文本、第三方 attribution/notice、机器可读合规元数据和重链接说明。

## 从源码开发 Bezel

贡献者以及暂未提供预编译包的平台仍使用源码构建。这条路径需要 Qt 6、CMake 和 C++17 编译器：

```bash
git clone https://github.com/turinglambdaai/bezel.git
cd bezel
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build
raco pkg install --auto --no-docs --link ./bezel-lib
raco pkg install --auto --no-docs --link ./bezel-test
raco pkg install --auto --no-docs --link ./bezel
QT_QPA_PLATFORM=offscreen raco test bezel-test/
```

开发构建若放在其他位置，可用 `BEZEL_LIBRARY` 指向共享库。手工解压 Release runtime 时，也可以用 `BEZEL_NATIVE_DIR` 指向 runtime 根目录。

## 架构

Bezel 有意把 native 边界控制得很小：

1. **C++ shim / 稳定 C ABI** —— Racket FFI 只面对扁平 C 函数；Qt 的 C++ 对象隐藏在经过校验的不透明句柄之后。
2. **协作式 GUI 线程编组** —— Qt 调用在 GUI 线程执行，同时避免在 C 侧做阻塞式跨线程交接，以免冻结 Racket CS 调度。
3. **信号桥** —— Qt signal → C++ sink → 同步队列 → Racket dispatcher → 用户 handler；handler 中的公开控件调用自动回到 GUI 线程。
4. **生命周期注册表** —— 遵循 Qt parent ownership，同时验证 live handle。无父对象会存活到显式删除或 application teardown；Bezel 刻意不用会删除 native 对象的 GC finalizer。
5. **生成绑定** —— JSON spec 同时生成 C++ 与 Racket 代码；生成的公开 API 与手写绑定共享存活检查、错误传播和 GUI 编组规则。

更深入的设计见 [docs/architecture.md](docs/architecture.md)。

## 平台支持状态

| 能力 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Application / 协作式运行循环 | ✅ | ✅ | ✅ |
| 核心控件 + 布局 | ✅ | ✅ | ✅ |
| 菜单 + 动作 | ✅ | ✅ | ✅ |
| 类型化信号（`bool` / `int` / `double` / `QString`） | ✅ | ✅ | ✅ |
| 跨线程公开控件访问 | ✅ | ✅ | ✅ |
| 生成绑定的线程编组 | ✅ | ✅ | ✅ |
| QSS 样式 | ✅ | ✅ | ✅ |
| `widget-grab-png` | ✅ | ✅ | ✅ |
| 无头真对象 CI | ✅ | ✅ | ✅ |
| 自包含发布包 | Apple Silicon | x86_64 | x86_64 |

暂不支持的 Qt signal 参数类型目前会退化为不带转换参数的投递。控件覆盖面当前仍是有意收敛的核心集合；扩展方向是 generator，而不是宣称已经覆盖整个 Qt。

## API 速览

### 应用生命周期

```racket
(make-application #:name "My App")
(run win)
(quit! 0)
```

`make-application` 是幂等的，并且必须在创建控件之前调用。`run` 是协作式 pump，而不是阻塞式 `exec`；默认情况下，最后一个可见窗口关闭后运行循环会停止。

### 控件与布局

```racket
(define win (make-window #:title "Team" #:size '(420 240) #:stylesheet qss))
(define name (make-line-edit))
(set-placeholder! name "Ada Lovelace")
(define experience (make-slider))
(set-widget-range! experience 0 15)

(layout! win
         (vbox #:margins '(20 20 20 20)
               (form (list "Name:" name)
                     (list "Experience:" experience))
               (hbox stretch (make-button "Submit"))))
```

树形组合（`vbox`、`hbox`、`grid`、`form`、`stretch`）和命令式 layout builder 都可以使用。

### 信号

```racket
(define conn-id
  (connect! btn "clicked()" (lambda _ (displayln "clicked!"))))
(connect! slider "valueChanged(int)" (lambda (v) (displayln v)))
(connect! edit "textChanged(QString)" (lambda (s) (displayln s)))
(disconnect! btn conn-id)
```

Handler 运行在 Bezel dispatcher 线程上。Handler 中调用公开控件 API 时，会自动编组回 GUI 线程。显式断连、目标对象销毁以及 application cleanup 都会同步回收 native connection 与 Racket handler。

### 验证能力

```racket
(define png (widget-grab-png win))
(process-events! 50)
(emit-test-signal! btn "clicked()")
```

仓库里的 showcase 图片本身就是 `scripts/showcase.rkt` 在无头 Qt 环境里生成的真实渲染结果。

### 对象生命周期

```racket
(bezel-alive? widget)
(bezel-delete! widget)
(qt-object-name widget)
(set-qt-object-name! widget "x")
(object-set-parent! widget parent)
```

所有权遵循 Qt parent 规则。Bezel 不做 GC 驱动的 native delete，从而避免迟到 finalizer 与复用 native 地址之间的竞态。

## Native runtime 搜索顺序

加载器按以下顺序寻找 `libbezel`：

1. `BEZEL_LIBRARY` —— 显式指定的共享库文件。
2. `BEZEL_NATIVE_DIR` —— 显式指定的解压 runtime 根目录。
3. `bezel-lib/native/<os>-<arch>/` —— 正常自包含发布包使用的 package-local runtime。
4. `bezel-shim/build` —— 源码 checkout 的开发便利路径。
5. 操作系统正常动态库搜索路径。

若发现随包携带的 Qt plugin 目录，而且应用没有主动设置 `QT_PLUGIN_PATH`，Bezel 会在构造 `QApplication` 前自动设置 package-local plugin path。

Native 加载遇到问题时直接运行：

```text
raco bezel doctor
```

## 发布工程

推送 `v*` tag 会触发 Release workflow。发布必须通过：

- `bezel-lib`、umbrella package、CMake shim、CHANGELOG 与 tag 的版本一致性检查；
- 生成绑定可重复性检查；
- 机器可读的 Qt 再分发策略、QtBase 6.8.4 精确源码哈希与官方补丁哈希检查；
- Qt/LGPL/第三方许可证与 attribution 材料生成；
- Qt 动态链接和各平台 package dependency boundary 检查；
- 三平台 native build；
- 便携 runtime 打包；
- 干净 runner 上的自包含 Racket package 安装与真 Qt 控件 smoke test（Linux 仅额外安装文档列明的发行版运行时前置包，不安装 Qt SDK、编译器或开发包）；
- 公共二进制旁同时发布经过校验的 QtBase 基础源码和已应用补丁包；
- Release SHA-256 清单生成。

三个公共 runtime 都从同一份经过校验的源码与补丁集合构建，保持 shared 动态库并禁用 ICU；Linux 保持非 Qt 系统库为宿主前置依赖，macOS 禁用已经过时的 OpenGL/AGL 路径，Windows 排除编译器、DXC、D3D compiler 和软件 OpenGL 运行库。这样不会让公共在线二进制悄悄偏离已审计的安全基线，也让每个平台的二进制与对应源码关系可复现、可审计。

完整检查表见 [docs/COMMERCIAL_RELEASE.md](docs/COMMERCIAL_RELEASE.md) 与 [docs/LGPL_RELINKING.md](docs/LGPL_RELINKING.md)。

## Qt 授权模型

Bezel 本身采用 MIT License。**Bezel 的公共 GitHub 预编译 runtime 路径被明确限制为 Qt LGPLv3 + 动态链接。** 发布包包含必要 notice/重链接材料，并与二进制一起发布经过校验的 QtBase 基础源码和已应用官方补丁。公共 workflow 会拒绝那种“仍然使用公共 Qt 构建，却只在变量里写成 commercial Qt”的发布方式。

专有商业产品当然可以采用 Qt 商业许可证，但应该使用单独的私有 release pipeline，并由许可证持有人使用真正受商业协议覆盖的 Qt 发行包和授权凭据构建；公共 Bezel workflow 不能被当作商业 Qt 授权来源的证明。

如果你的产品继续分发 Bezel 的公共 Qt 二进制，那么你的产品也成为再分发方，需要继续保留适用的 notices、对应源码可获得性和收件人的相关权利；最终 installer、签名/DRM、应用商店、设备锁定策略、合同条款以及你自己增加的依赖也需要单独评估。仓库里的自动化是强工程控制和审计链，不等价于针对某个具体商业产品的法律意见。

## 仓库结构

```text
bezel/
├── bezel/            # umbrella package
├── bezel-lib/        # Racket collection `bezel`
├── bezel-shim/       # C++ shim / C ABI
├── bezel-doc/        # Scribble 文档
├── bezel-test/       # 真对象无头测试
├── examples/         # hello / counter / form
├── scripts/          # 打包、smoke、showcase、release 检查
├── tools/generator/  # JSON spec -> C++ + Racket bindings
├── release/          # 机器可读 Qt 再分发策略
└── docs/             # 架构、许可证与商业发布说明
```

## 路线图

- [x] **Phase 1** —— C++ shim、C ABI、控件、布局、菜单、对话框。
- [x] **Phase 2** —— 类型化 signal bridge、协作式线程模型、生命周期注册表、generator。
- [x] **Phase 3** —— 三平台真对象 CI、PNG 验证、showcase。
- [x] **Phase 3.5** —— ABI guard、生命周期 hardening、生成绑定安全、可重复生成。
- [x] **Phase 4** —— 可迁移 native runtime、自包含 Racket package、干净机器安装 smoke、受 gate 保护的 GitHub Release。
- [x] **Phase 4.1** —— fail-closed LGPL 公共再分发、精确源码发布、包内 notice/relinking 材料、依赖边界强制检查。
- [ ] **Phase 5** —— 更广 Qt 类覆盖、更高层 API 易用性、最终应用打包/签名辅助工具。

## License

Bezel 使用 [MIT License](LICENSE)。随包重新分发的 Qt 组件及其第三方组件仍受各自适用的授权条款约束；公共二进制包会在 `LICENSES/` 中携带相应许可证与 attribution 材料。
