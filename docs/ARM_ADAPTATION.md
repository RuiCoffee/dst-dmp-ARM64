# ARM 架构适配说明

饥荒联机版（DST）服务端及 Valve 官方 `steamcmd` 均只提供 **x86 / x86_64 Linux** 二进制，
没有官方 ARM 版本。要在 ARM 服务器（如 aarch64 云主机、树莓派、RK3588 开发板等）上运行，
必须借助 [box64](https://github.com/ptitSeb/box64) 做用户态二进制翻译（将 x86/x86_64 指令
实时翻译为 ARM64 指令执行）。

本次改动的目标：**box64 本身仍需用户自行安装**（因为它高度依赖具体 ARM 板卡/系统，无法
在代码中自动保证可用），但一旦 box64 装好，DMP 的安装、更新、模组下载、开服等全部自动化
流程都应当在 ARM 环境下正常工作，不需要用户手动改代码或改命令。

## 核心思路

1. 用 `runtime.GOARCH` 判断当前是否运行在 ARM 架构（`arm64` / `arm`）。
2. 是 ARM 架构、且 `PATH` 中能找到 `box64` 命令时，所有原本直接调用 DST/steamcmd 这些
   x86 二进制的命令，自动在前面拼接 `box64 ` 前缀；非 ARM 架构下行为与原来完全一致。
3. DMP 自身（Go 后端）不依赖 CGO，可以原生编译并运行在 ARM 上，**不需要**也**不应该**用
   box64 去跑 DMP 自己。

## 代码改动一览

### 新增

- `utils/arch.go`
  - `IsARM()`：判断是否为 ARM 架构。
  - `Box64Available()` / `Box64Prefix()`：检测 box64 是否已安装并在 `PATH` 中。
  - `WrapX86Binary(cmd string) string`：给一段“直接执行 x86 ELF 二进制”的命令自动加上
    `box64 ` 前缀（非 ARM / box64 不可用时原样返回）。
  - `SteamCmdCmd(steamDir, args string) string`：统一生成 steamcmd 调用命令。
    - 非 ARM：`cd {steamDir} && ./steamcmd.sh {args}`（与原来完全一样）。
    - ARM 且 box64 可用：`cd {steamDir} && export LD_LIBRARY_PATH="$(pwd)/linux32:$LD_LIBRARY_PATH" && box64 linux32/steamcmd {args}`
      —— 按作者反馈，管理平台自动化调用场景下不建议再走 `steamcmd.sh` 脚本，而是
      通过 box64 直接调用 `linux32/steamcmd` 二进制。

### 修改

| 文件 | 改动内容 |
| --- | --- |
| `dst/utils.go` | `initInfo()` 中生成的开服命令（32-bit / 64-bit）改为通过 `utils.WrapX86Binary` 包装；luajit 模式外层不加 box64（原因见下）。 |
| `dst/mod.go` | `generateModDownloadCmd()` 改用 `utils.SteamCmdCmd("steamcmd", args)`。 |
| `app/dashboard/handler.go` | 手动"更新游戏"接口的 steamcmd 调用改用 `utils.SteamCmdCmd("~/steamcmd", args)`。 |
| `scheduler/global.go` | 定时任务"游戏更新"逻辑同上。 |
| `dst/room.go` | `runningScreen()` 原来用 `awk '{print $14}'` 按固定列号提取世界名，ARM 下由于命令行前多了 `box64` 一个 token，会导致所有列整体错位。改为 `awk` 动态查找 `-shard` 参数后面紧跟的值，不再依赖固定列号，两种架构下都正确。 |
| `embedFS/shell/manual_install.sh` | 增加 CPU 架构检测；ARM 架构下跳过 `dpkg --add-architecture i386`（ARM 主机无法添加 i386 外来架构），改为检查 box64 是否已安装；steamcmd 安装/首次拉取 DST 通过 `box64 ./steamcmd.sh ...` 执行；luajit 包装脚本内部按架构决定是否加 `box64` 前缀；libcurl-gnutls.so.4 无法在 ARM 上软链宿主机原生库，改为打印提示，需要用户自行放置 x86 版本的库文件。 |
| `embedFS/shell/manual_update.sh` | 同样增加架构检测，ARM 下通过 `box64 ./steamcmd.sh ...` 执行更新。 |
| `docker/Dockerfile` | 1) 修复了多架构交叉编译的 bug：原来 `go build` 没有显式设置 `GOARCH=$TARGETARCH`，`buildx` 多架构构建时后端二进制架构可能与目标镜像架构不一致；现在显式 `GOOS=${TARGETOS} GOARCH=${TARGETARCH}`。2) 运行时镜像按 `TARGETARCH` 分支：`amd64` 保持原来的 i386 依赖库安装；`arm64` 改为从 [box64-debs](https://ryanfortner.github.io/box64-debs/) 官方 APT 源安装通用 `box64` 包。 |
| `Makefile` | 新增 `backend-arm64` 目标，方便本地交叉编译 ARM64 版本二进制。 |

### 为什么 luajit 模式不在外层加 box64？

`dontstarve_dedicated_server_nullrenderer_x64_luajit` 并不是一个 ELF 可执行文件，而是
`manual_install.sh` 生成的一段 shell 脚本，作用是设置 `LD_PRELOAD` 之后再调用真正的
`dontstarve_dedicated_server_nullrenderer_x64` ELF 二进制。box64 只能翻译执行 x86 ELF 文件，
不能直接“翻译”一个 shell 脚本。所以正确的做法是让 box64 出现在脚本**内部**真正调用 ELF
二进制的那一行，而不是包在脚本外层——这正是 `manual_install.sh` 里针对 ARM 架构生成的
版本所做的事情。

## 仍需用户手动完成的部分

1. **安装 box64**：请参考 [box64 官方仓库](https://github.com/ptitSeb/box64) 或
   [box64-debs](https://ryanfortner.github.io/box64-debs/)（提供预编译的 APT 源，其中
   `box64` 为通用 arm64 包，另外还有针对树莓派、RK3588 等 SoC 优化的包）自行安装，并
   确保 `box64` 命令在 `PATH` 中可以直接找到（`which box64` 有输出）。
2. **x86 版本的 `libcurl-gnutls.so.4`**：DST 服务端启动时需要加载这个库。amd64 环境下脚本
   会自动软链系统自带的 x86 版本；但 ARM 宿主机上没有原生 x86 版本的这个库，需要用户自行
   获取（例如从 box64 社区提供的 x86 rootfs、或从任意一台 x86 Linux 主机复制过来）后放到
   `dst/bin/lib32/libcurl-gnutls.so.4` 和 `dst/bin64/lib64/libcurl-gnutls.so.4`。若启动日志
   中出现类似 `libcurl-gnutls.so.4: cannot open shared object file` 的报错，多半就是这一步
   没有做。
3. **Docker 部署**：若 `docker/Dockerfile` 中 box64-debs 的 APT 源在你的网络环境下无法访问，
   请把该源换成可访问的镜像地址，或者改为在宿主机编译好 box64 后通过 volume 挂载进容器。

## 验证方式

- `./dmp -v` 之外，可以额外确认：日志等级调到 `debug` 后，日志中打印的开服命令（`world.startCmd`）
  在 ARM 环境下应类似：
  ```
  cd dst/bin64/ && screen -d -h 200 -m -S DMP_Cluster_1_World1 box64 ./dontstarve_dedicated_server_nullrenderer_x64 -console -cluster Cluster_1 -shard World1
  ```
- 模组下载 / 游戏更新触发的 steamcmd 命令，在 ARM 环境下应类似：
  ```
  cd steamcmd && export LD_LIBRARY_PATH="$(pwd)/linux32:$LD_LIBRARY_PATH" && box64 linux32/steamcmd +login anonymous ... +quit
  ```
- `dst/version.txt` 的检测逻辑（`scheduler/utils.go` 的 `GetDSTVersion()`）本身只是读取一个
  文本文件，与架构无关，未做改动，ARM 下同样适用。
