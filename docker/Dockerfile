# 第1阶段：构建应用程序
FROM --platform=$BUILDPLATFORM golang:1.25 AS build

ARG GOPROXY
ARG GOSUMDB
ARG GOPRIVATE
ARG TARGETARCH
ARG TARGETOS=linux

WORKDIR /app

# 设置GO111MODULE环境变量为on，启用Go模块支持 (此行注释掉，可能已默认启用)
# ENV GO111MODULE=on

# 复制当前目录下的所有文件到容器的/app目录
COPY . .

# 交叉编译到目标架构（linux/amd64、linux/arm64 等），DMP 后端本身不含 CGO 依赖，
# 可原生编译运行于 ARM 架构；DST 服务端仍为 x86 二进制，运行时依赖 box64 转译（见下文）
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags '-s -w' -v -o dmp main.go


# 第2阶段：运行时环境
FROM ubuntu:24.04

ARG TARGETARCH

WORKDIR /root

# 从构建阶段复制必要的文件
COPY --from=build /app/dmp /root/dmp
COPY --from=build /app/docker/entry-point.sh /root/entry-point.sh

# amd64：安装 i386 依赖库，用于运行 DST 官方 x86 二进制
# arm64：DST 服务端仍是 x86 二进制，需要 box64 进行用户态二进制翻译才能运行，
#        这里从 box64 官方 APT 源（https://ryanfortner.github.io/box64-debs/）安装通用 arm64 版 box64；
#        如需针对特定 SoC（如 RK3588、树莓派等）的优化版本，可自行替换为对应包名，
#        或在网络环境无法访问该源时改为在宿主机自行编译安装 box64 后挂载进容器
RUN set -e; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        apt-get update && \
        apt-get install -y gnupg wget screen && \
        wget https://ryanfortner.github.io/box64-debs/box64.list -O /etc/apt/sources.list.d/box64.list && \
        wget -qO- https://ryanfortner.github.io/box64-debs/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/box64-debs-archive-keyring.gpg && \
        apt-get update && \
        apt-get install -y box64 && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        dpkg --add-architecture i386 && \
        apt-get update && \
        apt-get install -y libcurl4-gnutls-dev:i386 && \
        apt-get install -y screen wget && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi
RUN chmod +x /root/dmp /root/entry-point.sh
RUN mkdir -p /root/data /root/.klei

# 环境变量
# - 平台暴露端口，默认为80
ENV DMP_PORT=80
# 是否以容器方式启动
ENV DMP_IN_CONTAINER=1

# web端口
EXPOSE 80/tcp

# 设置容器启动时执行的脚本
ENTRYPOINT ["/root/entry-point.sh"]
