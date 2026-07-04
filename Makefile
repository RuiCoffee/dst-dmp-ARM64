FRONTEND_DIR := $(HOME)/WebstormProjects/dst-management-platform-web
EMBED_DIR := embedFS/dist

.PHONY: all frontend backend clean

all: frontend copy-frontend backend

frontend:
	@echo "=== Building frontend ==="
	cd $(FRONTEND_DIR) && npx vite build

clean-embed:
	@echo "=== Cleaning embedFS/dist ==="
	rm -rf $(EMBED_DIR)/*

backend:
	@echo "=== Building backend ==="
	CGO_ENABLED=0 go build -ldflags '-s -w' -v -o dmp

# 交叉编译 ARM64 版本后端（DMP 自身无 CGO 依赖，可原生编译运行于 ARM 架构；
# 注意：DST 服务端及 steamcmd 仍为 x86 二进制，ARM 运行环境需自行安装 box64）
backend-arm64:
	@echo "=== Building backend (linux/arm64) ==="
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags '-s -w' -v -o dmp-arm64

# 复制前端产物到 embedFS/dist（不重新构建前端）
copy-frontend:
	@echo "=== Copying frontend dist ==="
	rm -rf $(EMBED_DIR)/*
	cp -r $(FRONTEND_DIR)/dist/* $(EMBED_DIR)/
