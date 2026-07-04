package utils

import (
	"fmt"
	"os/exec"
	"runtime"
	"sync"
)

// IsARM 判断当前运行环境是否为 ARM 架构（arm64/arm）。
// DST 服务端及 steamcmd 官方仅提供 x86/x86_64 Linux 二进制，
// 在 ARM 架构下需要借助 box64 进行用户态二进制翻译才能运行。
func IsARM() bool {
	switch runtime.GOARCH {
	case "arm64", "arm":
		return true
	default:
		return false
	}
}

var (
	box64PathOnce  sync.Once
	box64Path      string
	box64Available bool
)

// Box64Path 查找 box64 可执行文件的绝对路径。
// 非 ARM 架构下始终返回空字符串。
func Box64Path() string {
	if !IsARM() {
		return ""
	}

	box64PathOnce.Do(func() {
		p, err := exec.LookPath("box64")
		if err == nil {
			box64Path = p
			box64Available = true
		}
	})

	return box64Path
}

// Box64Available 判断当前环境下 box64 是否可用（已安装且在 PATH 中）。
// 非 ARM 架构下始终返回 false（不需要）。
func Box64Available() bool {
	if !IsARM() {
		return false
	}
	_ = Box64Path()
	return box64Available
}

// Box64Prefix 返回运行 x86/x86_64 二进制程序前需要拼接的命令前缀。
// 在 ARM 架构且 box64 可用时返回 "box64 "，其他情况返回空字符串，
// 调用方直接拼接到命令字符串前即可，兼容非 ARM 架构下的原有行为。
func Box64Prefix() string {
	if Box64Available() {
		return "box64 "
	}
	return ""
}

// WrapX86Binary 将一段执行 x86/x86_64 二进制的命令（如 "./dst_server ..."）
// 根据当前架构自动包装为可执行的命令：
//   - 非 ARM 架构：原样返回
//   - ARM 架构且 box64 可用：在命令前拼接 "box64 "
//   - ARM 架构但 box64 不可用：原样返回（调用方应结合日志提示用户安装 box64）
func WrapX86Binary(cmd string) string {
	prefix := Box64Prefix()
	if prefix == "" {
		return cmd
	}
	return prefix + cmd
}

// SteamCmdCmd 生成在指定 steamcmd 目录下执行 steamcmd 的完整命令。
//
//   - steamDir：steamcmd 所在目录，可以是相对路径（如 "steamcmd"），也可以是 "~/steamcmd"
//   - args：传递给 steamcmd 的参数，例如 "+login anonymous +quit"
//
// 非 ARM 架构下沿用官方 steamcmd.sh 启动脚本：
//
//	cd {steamDir} && ./steamcmd.sh {args}
//
// ARM 架构下，steamcmd.sh 脚本自身包含的更新/校验逻辑在 box64 转译环境中运行不稳定，
// 因此直接通过 box64 调用 linux32/steamcmd 二进制，并手动设置其依赖的动态库路径：
//
//	cd {steamDir} && export LD_LIBRARY_PATH="$(pwd)/linux32:$LD_LIBRARY_PATH" && box64 linux32/steamcmd {args}
//
// 若 ARM 架构下未检测到 box64，则回退为官方脚本调用方式（大概率无法正常运行，
// 但便于通过日志向用户提示需要安装 box64）。
func SteamCmdCmd(steamDir string, args string) string {
	if IsARM() {
		if prefix := Box64Prefix(); prefix != "" {
			return fmt.Sprintf(`cd %s && export LD_LIBRARY_PATH="$(pwd)/linux32:$LD_LIBRARY_PATH" && %slinux32/steamcmd %s`, steamDir, prefix, args)
		}
	}
	return fmt.Sprintf("cd %s && ./steamcmd.sh %s", steamDir, args)
}
