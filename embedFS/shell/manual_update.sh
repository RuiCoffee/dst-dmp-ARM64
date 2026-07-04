#!/bin/bash

# 设置错误处理
set -e

# 错误处理函数
function error_exit() {
    echo -e "==>dmp@@ 更新失败 @@dmp<=="
    exit 1
}

# 设置trap捕获所有错误
trap error_exit ERR

# DST 服务端及 steamcmd 官方仅提供 x86 Linux 二进制，ARM 架构下需要 box64 转译运行
MACHINE_ARCH=$(uname -m)
case "${MACHINE_ARCH}" in
    x86_64|amd64)
        IS_ARM=0
        ;;
    aarch64|arm64|armv7l|armv8l|armv7|armv8)
        IS_ARM=1
        if ! which box64 > /dev/null 2>&1; then
            echo -e "未检测到 box64 命令，ARM 架构下无法运行 steamcmd，请先安装 box64"
            error_exit
        fi
        ;;
    *)
        echo -e "不支持的CPU架构: ${MACHINE_ARCH}"
        error_exit
        ;;
esac

cd steamcmd || error_exit
if [[ "${IS_ARM}" == "1" ]]; then
    box64 ./steamcmd.sh +login anonymous +force_install_dir ~/dst +app_update 343050 validate +quit || error_exit
else
    ./steamcmd.sh +login anonymous +force_install_dir ~/dst +app_update 343050 validate +quit || error_exit
fi

cd || true

# 安装完成
echo -e "==>dmp@@ 更新完成 @@dmp<=="