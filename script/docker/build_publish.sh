#!/bin/bash

# 登录阿里云 Registry (仅需执行一次):
# docker login --username=liamjing registry.cn-beijing.aliyuncs.com

# 遇到错误立即退出
set -e

# ========================================================
# 配置信息
# ========================================================
REGISTRY="registry.cn-beijing.aliyuncs.com"
NAMESPACE="liam_test"
# 默认版本为 latest，也可通过第一个参数传入，如 ./build_publish.sh v1.0.0
VERSION="${1:-latest}" 

# ========================================================
# 目录路径计算
# ========================================================
# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# 项目根目录 (假设脚本在 script/docker，回退两级)
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../" && pwd )"

# 后端目录 (即项目根目录)
BACKEND_DIR="$PROJECT_ROOT"
# 前端目录 (假设与后端项目同级)
FRONTEND_DIR="$( cd "$PROJECT_ROOT/../yudao-ui-admin-vue3" && pwd )"

# ========================================================
# 开始构建
# ========================================================
echo "========================================================"
echo "🚀 开始构建并推送镜像"
echo "--------------------------------------------------------"
echo "目标架构: linux/amd64 (使用 Rosetta/QEMU 模拟)"
echo "镜像仓库: $REGISTRY/$NAMESPACE"
echo "镜像版本: $VERSION"
echo "后端路径: $BACKEND_DIR"
echo "前端路径: $FRONTEND_DIR"
echo "========================================================"

# 检查前端目录是否存在
if [ ! -d "$FRONTEND_DIR" ]; then
    echo "❌ 错误: 找不到前端目录"
    echo "期望路径: $FRONTEND_DIR"
    echo "请确认 yudao-ui-admin-vue3 与 ruoyi-vue-pro 位于同一级目录"
    exit 1
fi

# --------------------------------------------------------
# 1. 构建后端 (Ruoyi-Vue-Pro)
# --------------------------------------------------------
echo ""
echo "[1/2] 📦 正在处理后端 (ruoyi-vue-pro)..."
cd "$BACKEND_DIR"

echo "   -> 开始构建 Docker 镜像..."
# 使用 --platform linux/amd64 进行跨平台构建
docker build --platform linux/amd64 \
    -t "${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}" \
    -f Dockerfile .

echo "   -> 正在推送镜像到阿里云..."
docker push "${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}"

echo "✅ 后端镜像处理完成！"

# --------------------------------------------------------
# 2. 构建前端 (Yudao-UI-Admin-Vue3)
# --------------------------------------------------------
echo ""
echo "[2/2] 🎨 正在处理前端 (yudao-ui-admin-vue3)..."
cd "$FRONTEND_DIR"

echo "   -> 开始构建 Docker 镜像..."
docker build --platform linux/amd64 \
    -t "${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}" \
    -f Dockerfile .

echo "   -> 正在推送镜像到阿里云..."
docker push "${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}"

echo "✅ 前端镜像处理完成！"

# ========================================================
# 结束
# ========================================================
echo ""
echo "========================================================"
echo "🎉 所有任务执行成功！"
echo "--------------------------------------------------------"
echo "后端镜像: ${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}"
echo "前端镜像: ${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}"
echo "========================================================"
