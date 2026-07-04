#!/bin/bash

# 设置错误处理
set -e

# 定义变量
STEAM_DIR="$HOME/steamcmd"
DST_DIR="$HOME/dst"

# 错误处理函数
function error_exit() {
    echo -e "==>dmp@@ 安装失败 @@dmp<=="
    exit 1
}

# 设置trap捕获所有错误
trap error_exit ERR

# 架构检测：DST 服务端及 steamcmd 官方仅提供 x86/x86_64 Linux 二进制，
# ARM 架构（arm64/aarch64/armv7 等）下需要通过 box64 进行用户态二进制翻译才能运行
MACHINE_ARCH=$(uname -m)
case "${MACHINE_ARCH}" in
    x86_64|amd64)
        IS_ARM=0
        ;;
    aarch64|arm64|armv7l|armv8l|armv7|armv8)
        IS_ARM=1
        ;;
    *)
        echo -e "不支持的CPU架构: ${MACHINE_ARCH}"
        error_exit
        ;;
esac

# 检查 box64 是否已安装（仅 ARM 架构需要）
function check_box64() {
    if ! which box64 > /dev/null 2>&1; then
        echo -e "未检测到 box64 命令"
        echo -e "ARM 架构下运行饥荒服务端及 steamcmd 依赖 box64 进行 x86 二进制翻译"
        echo -e "请参考 https://github.com/ptitSeb/box64 自行安装 box64 后重新执行安装"
        error_exit
    fi
}

# 工具函数
function install_ubuntu() {
    apt update -y
    apt install -y screen wget curl
    if [[ "${IS_ARM}" == "1" ]]; then
        # ARM 架构无法通过 dpkg 添加 i386 外来架构，相关 x86 依赖库由 box64 自行处理，
        # 这里仅确保基础工具已安装，box64 需由用户提前安装好
        check_box64
    else
        dpkg --add-architecture i386
        apt update -y
        apt install -y lib32gcc1 || true
        apt install -y lib32gcc-s1 || true
        apt install -y libcurl4-gnutls-dev:i386 || error_exit
        apt install -y libcurl4-gnutls-dev || true
    fi
}

function install_rhel() {
    yum update -y
    yum -y install screen wget curl
    if [[ "${IS_ARM}" == "1" ]]; then
        check_box64
    else
        yum -y install glibc.i686 libstdc++.i686 libcurl.i686
        yum -y install glibc libstdc++ libcurl
        ln -s /usr/lib/libcurl.so.4 /usr/lib/libcurl-gnutls.so.4
    fi
}

function check_screen() {
    if ! which screen > /dev/null 2>&1; then
        echo -e "screen命令安装失败"
        error_exit
    fi
}

function check_wget() {
    if ! which wget > /dev/null 2>&1; then
        echo -e "wget命令安装失败"
        error_exit
    fi
}

# 安装依赖
OS=$(grep -P "^ID=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g")
if [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
    install_ubuntu
else
    if grep -P "^ID_LIKE=" /etc/os-release | awk -F'=' '{print($2)}' | sed "s/['\"]//g" | grep rhel > /dev/null 2>&1; then
        install_rhel
    else
        echo -e "系统不支持"
        error_exit
    fi
fi

# 检查screen命令
check_screen

# 检查wget命令
check_wget

# 下载安装包
cd "$HOME" || error_exit
rm -f steamcmd_linux.tar.gz
wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

# 清理，容器中不删除steamcmd
if [[ "${DMP_IN_CONTAINER}" != "1" ]] ;then
	rm -rf "$STEAM_DIR"
fi
mkdir -p "$STEAM_DIR"

# 解压安装包
tar -zxvf steamcmd_linux.tar.gz -C "$STEAM_DIR"

# 安装DST
cd "$STEAM_DIR" || error_exit
if [[ "${IS_ARM}" == "1" ]]; then
    # ARM 架构下 steamcmd 是 x86 二进制，需要通过 box64 转译运行
    # 注：安装/引导阶段仍使用 steamcmd.sh 脚本（box64 可以正常转译执行它），
    # 管理平台后续的自动化调用（模组下载、游戏更新）会直接通过 box64 调用
    # steamcmd/linux32/steamcmd 二进制，详见 utils.SteamCmdCmd
    box64 ./steamcmd.sh +force_install_dir "$DST_DIR" +login anonymous +app_update 343050 validate +quit || true
    # 第一次安装dst可能会失败
    box64 ./steamcmd.sh +force_install_dir "$DST_DIR" +login anonymous +app_update 343050 validate +quit
else
    ./steamcmd.sh +force_install_dir "$DST_DIR" +login anonymous +app_update 343050 validate +quit || true
    # 第一次安装dst可能会失败
    ./steamcmd.sh +force_install_dir "$DST_DIR" +login anonymous +app_update 343050 validate +quit
fi

# PR77 清理可能损坏的acf文件
rm -rf "$DST_DIR/steamapps/appmanifest_343050.acf"

# 一些必要的so文件
cd "$HOME" || error_exit
cp steamcmd/linux32/libstdc++.so.6 dst/bin/lib32/
if [[ "${IS_ARM}" == "1" ]]; then
    # ARM 宿主机没有原生 x86/x86_64 版本的 libcurl-gnutls.so.4，无法直接软链宿主机的库文件，
    # DST 服务端启动若提示缺少该库，请自行放置对应架构（x86/x86_64）的 libcurl-gnutls.so.4
    # 到 dst/bin/lib32/ 和 dst/bin64/lib64/ 目录下（可从 box64 社区提供的 rootfs 中获取）
    echo -e "提示：ARM 架构下请确认 dst/bin/lib32/ 与 dst/bin64/lib64/ 目录下已具备 x86 版本的 libcurl-gnutls.so.4，如启动报错缺库请手动补充"
elif [[ "${OS}" == "ubuntu" || "${OS}" == "debian" ]]; then
	[ ! -L "dst/bin64/lib64/libcurl-gnutls.so.4" ] && ln -s /usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4 dst/bin64/lib64/libcurl-gnutls.so.4
	[ ! -L "dst/bin/lib32/libcurl-gnutls.so.4" ] && ln -s /usr/lib/i386-linux-gnu/libcurl-gnutls.so.4 dst/bin/lib32/libcurl-gnutls.so.4
else
	[ ! -L "dst/bin64/lib64/libcurl-gnutls.so.4" ] && ln -s /usr/lib64/libcurl.so.4 dst/bin64/lib64/libcurl-gnutls.so.4
	[ ! -L "dst/bin/lib32/libcurl-gnutls.so.4" ] && ln -s /usr/lib/libcurl.so.4 dst/bin/lib32/libcurl-gnutls.so.4
fi

# luajit
cd "$HOME" || error_exit
cp dmp_files/luajit/* dst/bin64/
if [[ "${IS_ARM}" == "1" ]]; then
    # ARM 架构下需要在包装脚本内部调用 box64 来转译执行真正的 x64 ELF 二进制
    cat >dst/bin64/dontstarve_dedicated_server_nullrenderer_x64_luajit <<-"EOF"
export LD_PRELOAD=./libpreload.so
box64 ./dontstarve_dedicated_server_nullrenderer_x64 "$@"
unset LD_PRELOAD
EOF
else
    cat >dst/bin64/dontstarve_dedicated_server_nullrenderer_x64_luajit <<-"EOF"
export LD_PRELOAD=./libpreload.so
./dontstarve_dedicated_server_nullrenderer_x64 "$@"
unset LD_PRELOAD
EOF
fi
chmod --reference=dst/bin64/dontstarve_dedicated_server_nullrenderer_x64 dst/bin64/dontstarve_dedicated_server_nullrenderer_x64_luajit

# 清理
cd "$HOME" || error_exit
rm -f steamcmd_linux.tar.gz

# 安装完成
echo -e "==>dmp@@ 安装完成 @@dmp<=="