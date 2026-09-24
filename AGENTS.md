# AGENTS.md

指引给 AI agent（及开发者）：如何理解、构建、测试、改动 Bezel。

## 这是什么

Bezel 把 Qt 6（Widgets）绑定到 Racket：Racket 写应用，三平台原生控件。
四层架构（自上而下）：

1. **safe layer**（`bezel-lib/bezel/*.rkt`）：`make-window` / `widget-set-text!` /
   `connect!` / `run` 等公开 API，负责错误检查、所有权翻转、字符串转换
2. **marshal + raw**（`bezel-lib/private/{marshal,raw}.rkt`）：所有 raw 调用经
   `gui` 编组到 GUI 线程（协作式，绝不裸阻塞）；kebab→snake 符号映射
3. **dispatcher 线程**（`bezel-lib/private/dispatch.rkt`）：轮询信号队列，
   在 Racket 线程里执行用户 handler
4. **C++ shim**（`bezel-shim/src/*.cpp`，C ABI）：不透明句柄上的扁平函数、
   信号队列、句柄注册表、PNG 截图

`bezel-shim/include/bezel/bezel.h` 是**全部 C 契约**——改 shim 前先读它。

## 核心不变量（破坏会死锁/崩溃）

- **C 侧从不在跨线程交接处等待**（无 BlockingQueuedConnection、无裸
  semaphore/condvar）。Racket CS 线程会漂移 OS 线程，裸外国阻塞会冻住整个
  调度器。等待只能发生在 Racket 侧（`sync/timeout` 信号量）。
- **Qt 调用只在 GUI 线程执行**：非 GUI 线程的调用经 marshal 队列，由泵
  （`run` / `process-events!` 里的 `drain-gui!`）排水。
- **`run` 是泵循环，不是 `QApplication::exec`**——阻塞 exec 会饿死
  dispatcher 线程，所有 handler 永远不触发。泵的退出条件：`quit!`，或
  「已显示过窗口且当前无可见顶层窗口」（即 quit-on-last-window-closed，
  见 `bezel_app_quit_requested`；`set-quit-on-last-window-closed!` 可关）。
- **Qt 内联调用的判定是「Racket 主线程」而非 OS 线程**——Racket CS 线程
  会复用 OS 线程，`QThread::currentThread()` 对工作线程也可能返回"在
  GUI 线程上"，此时内联调用会把 OS 线程楔死（编组判定在
  `private/marshal.rkt` 的 `gui`）。
- **handler 永不直接跑在 Qt 线程上**：Qt 信号 → C++ sink → 队列 →
  dispatcher（Racket 线程）→ 用户过程。
- **`bezel.h` 里的结构体字段序**：天然对齐字段在前、`int8 tag` 在最后——
  Racket 的 `define-cstruct` 紧凑布局无填充，这是两侧逐字节一致的唯一排法。
  改字段序必须同时改 `private/ctypes.rkt`。
- **所有权/生命周期**：对象活到 app 退出（cleanup 统一销毁）或显式
  `bezel-delete!`；**没有删除型 finalizer**——迟到的 finalizer 会命中被
  Qt 释放并复用的堆地址，误删无辜控件（Windows 上实测）。`layout!` 把
  所有权移交 Qt 仅是语义记录。`bezel-object-delete` 在 unmarshaled
  排除名单里（finalizer/退场阶段不得经编组队列等待）。
- **`bezel-cleanup!` 会杀掉 dispatcher 线程**（shutdown 标志）；
  `make-application` 重建 app 时 `ensure-dispatcher!` 负责复活它——
  新增"只启动一次"式的全局资源时，记得同样处理重建场景。

## 快速命令

```bash
# 构建 shim（macOS 先 brew install qt cmake；Linux 装 qt6-base-dev）
cmake -S bezel-shim -B bezel-shim/build -DCMAKE_BUILD_TYPE=Release
cmake --build bezel-shim/build -j

# 链接 Racket 包（本地开发）
raco pkg install --auto --no-docs --link ./bezel-lib ./bezel ./bezel-test

# 编译
raco make bezel-lib/main.rkt

# 测试（无头，三平台同套件；必须设 offscreen）
QT_QPA_PLATFORM=offscreen raco test bezel-test/

# 跑 GUI 示例（开真窗口）
racket examples/hello.rkt
racket examples/counter.rkt

# 重新生成 README showcase 截图（无头）
QT_QPA_PLATFORM=offscreen racket scripts/showcase.rkt docs/showcase.png
```

## 项目结构

```
bezel/                # 元包：`raco pkg install bezel` 装齐下列全部
bezel-lib/            # 核心库（collection `bezel`）
├── app.rkt           # make-application / run（泵循环）/ quit!
├── widgets.rkt       # 构造器 + 共享控件 API + grab_png + 表格/树/日期/tooltip/几何
├── layouts.rkt       # 树形（vbox/hbox/grid/form/stretch）+ 命令式
├── menus.rkt         # menu-bar / menu! / set-action-shortcut! / 状态栏/工具栏
├── dialogs.rkt       # msg-information / warning / question + 文件对话框
├── signals.rkt       # connect! / disconnect! / emit-test-signal!
├── timers.rkt        # after! / every! / stop-timer!（纯 Racket 线程调度）
├── desktop.rkt       # 剪贴板 + 系统托盘/通知
├── sentry.rkt        # Sentry 兼容错误上报（纯 Racket，无 Qt 依赖，本地可测）
├── updates.rkt       # check-for-update / check-and-prompt-update!（静态 JSON 清单，尽力而为）
├── cli.rkt           # raco bezel doctor | package
├── main.rkt          # umbrella
└── private/
    ├── lib.rkt       # libbezel 查找（$BEZEL_LIBRARY → native 目录们 → build 目录 → 系统）
    ├── raw.rkt       # define-bezel：kebab→snake + 全量编组（经 gui）
    ├── marshal.rkt   # gui / drain-gui!：协作式编组队列
    ├── dispatch.rkt  # dispatcher 线程：bezel-next-signal 轮询 + handler 分发
    ├── objects.rkt   # bezel-object 句柄 + 所有权 + finalizer
    ├── pack.rkt      # raco bezel package 的打包引擎（raco exe --embed + runtime 拷贝）
    ├── errors.rkt    # exn:fail:bezel + ok!/ok-handle/ok-string
    ├── ctypes.rkt    # variant / signal-msg 结构体（镜像 bezel.h）
    └── generated/    # 生成器产物（dial_gen.rkt 等 9 个模块）
bezel-shim/           # C++ shim（CMake；AUTOMOC 开）
├── include/bezel/bezel.h   # C ABI 契约（文档齐全）
└── src/
    ├── core.cpp      # app 生命周期 / on_gui / 句柄注册表 / 信号队列
    ├── widgets.cpp   # 控件构造器 + 值 API + grab_png + 表格/树/日期/tooltip/几何
    ├── dialogs.cpp   # 文件对话框（与 msg-* 同为阻塞式模态约定）
    ├── tray.cpp       # 剪贴板 + 系统托盘（QClipboard/QSystemTrayIcon）
    ├── layouts.cpp   # 布局 / 菜单 / msg 对话框
    ├── signals.cpp   # 信号桥：sink 连接 + 队列 + emit 测试钩子
    ├── signalsink.h  # 每连接 sink（Q_OBJECT，AUTOMOC）
    └── generated/    # 生成器产物（dial_gen.cpp 等 9 个文件）
tools/generator/      # JSON spec → shim + Racket 双侧代码（specs/ 下 9 个 spec）
docs/architecture.md  # 深入设计（先读这个再改 private/ 或 shim/）
docs/APP_PACKAGING.md # 最终应用打包 + 签名流程
```

## 常见任务指引

- **加一个控件/方法（手工精修路径）**：`bezel.h` 加声明 → shim 对应 .cpp
  实现（Qt 工作放进 `on_gui(...)` lambda）→ `raw.rkt` 加 `define-bezel` →
  safe 层加包装（`require-alive!` + `ok!`）→ 测试。
- **加一类控件（规模化路径）**：写 `tools/generator/specs/*.json`，跑
  `racket tools/generator/generate.rkt <spec>`，CMake 已 glob
  `src/generated/*.cpp`，`main.rkt` require 生成模块。参考 `specs/dial.json`。
  参数类型支持 parent/widget/string/int/double/bool；`orientation` 是
  C 侧 int、Qt 侧 `static_cast<Qt::Orientation>`（1/2 = 水平/垂直）。
- **加类型化信号**：`signalsink.h` 加 slot（按首参类型），`slot_for_signal`
  加映射；或用生成器的 `signals` 字段登记文档。
- **改泵行为**：`app.rkt` 的 `run`（`#:fps` 控制帧率）；泵必须同时做
  `process-events` + `drain-gui!` + `sleep` 让出，缺一不可。
- **调试信号不达**：按序查 (1) dispatcher 活着吗（`ensure-dispatcher!`
  在 cleanup 后要复活）；(2) sink slot 类型匹配吗（`slot_for_signal`）；
  (3) 泵在排水吗。

## 已知陷阱

- `define-cstruct` 的字段名不能用 `tag`（与内部 type-tag 冲突）——本库用 `vt`。
- `define-cstruct` 自动定义 `<type>-pointer` 与访问器，勿重复定义。
- Racket CS：`make-sized-byte-string` 不可用（用 `malloc` + `memcpy`）；
  `ptr-set!` 对 cstruct 不可靠（用 `cvector`）；`case` 子句不求值（变量
  常量会按字面 symbol 比较）。
- MSVC 与 clang 的 `__attribute__((format(printf,...)))` 不同——shim 里
  `set_error` 的属性声明已用 `__GNUC__` 包裹（Windows CI 验证）。
