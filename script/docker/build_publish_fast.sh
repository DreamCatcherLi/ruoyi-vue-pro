#!/bin/bash

# 遇到错误立即退出
set -e

# ========================================================
# 配置信息
# ========================================================
REGISTRY="registry.cn-beijing.aliyuncs.com"
NAMESPACE="liam_test"

# 参数解析
# 用法: ./build_publish_fast.sh [all|backend|frontend] [version]
MODE="${1:-all}"
VERSION="${2:-latest}" 

# 如果第一个参数看起来像版本号（以 v 开头），则假定模式为 all，并将第一个参数视为版本
if [[ "$MODE" == v* ]]; then
    VERSION="$MODE"
    MODE="all"
fi

# 帮助信息
if [[ "$MODE" == "help" || "$MODE" == "-h" || "$MODE" == "--help" ]]; then
    echo "========================================================"
    echo "💡 极速构建脚本使用说明"
    echo "========================================================"
    echo "用法: ./build_publish_fast.sh [COMMAND] [VERSION]"
    echo ""
    echo "命令 (COMMAND):"
    echo "  all       (默认) 顺序构建后端和前端"
    echo "  backend   仅构建后端 (ruoyi-vue-pro)"
    echo "  frontend  仅构建前端 (yudao-ui-admin-vue3)"
    echo "  parallel  并行构建后端和前端 (速度最快)"
    echo "  help      显示此帮助信息"
    echo ""
    echo "版本 (VERSION):"
    echo "  可选，默认为 'latest'。例如: v1.0.0"
    echo ""
    echo "示例:"
    echo "  ./build_publish_fast.sh                   # 构建所有 (latest)"
    echo "  ./build_publish_fast.sh backend           # 仅构建后端"
    echo "  ./build_publish_fast.sh parallel v1.2.0   # 并行构建 v1.2.0 版本"
    exit 0
fi

# ========================================================
# 目录路径计算
# ========================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../" && pwd )"
BACKEND_DIR="$PROJECT_ROOT"
FRONTEND_DIR="$( cd "$PROJECT_ROOT/../yudao-ui-admin-vue3" && pwd )"

echo "========================================================"
echo "🚀 开始极速构建 (Local Build + Docker Package)"
echo "--------------------------------------------------------"
echo "构建模式: $MODE"
echo "目标架构: linux/amd64"
echo "镜像版本: $VERSION"
echo "镜像仓库: $REGISTRY/$NAMESPACE"
echo "========================================================"

# ========================================================
# 函数定义
# ========================================================

build_backend() {
    echo ""
    echo "--------------------------------------------------------"
    echo "[后端] 📦 正在处理 (ruoyi-vue-pro)..."
    echo "--------------------------------------------------------"
    
    # 切换到后端目录
    cd "$BACKEND_DIR"

    echo "   -> ☕️ [Step 1] 本地编译 Java 代码..."
    # 跳过测试以加快速度
    mvn clean package -DskipTests -Dmaven.test.skip=true

    echo "   -> 🐳 [Step 2] 构建 Docker 镜像 (COPY Jar)..."
    docker build --platform linux/amd64 \
        -t "${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}" \
        -f Dockerfile.local .

    echo "   -> ⬆️ [Step 3] 推送镜像..."
    docker push "${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}"

    echo "✅ 后端处理完成！"
}

build_frontend() {
    echo ""
    echo "--------------------------------------------------------"
    echo "[前端] 🎨 正在处理 (yudao-ui-admin-vue3)..."
    echo "--------------------------------------------------------"
    
    # 检查前端目录
    if [ ! -d "$FRONTEND_DIR" ]; then
        echo "❌ 错误: 找不到前端目录 $FRONTEND_DIR"
        exit 1
    fi
    cd "$FRONTEND_DIR"

    echo "   -> 🔨 [Step 1] 本地编译 Vue 代码..."
    if ! command -v pnpm &> /dev/null; then
        echo "❌ 错误: 未找到 pnpm 命令，请先安装: npm install -g pnpm"
        exit 1
    fi
    pnpm install --frozen-lockfile
    pnpm run build:prod

    echo "   -> 🐳 [Step 2] 构建 Docker 镜像 (COPY Dist)..."
    docker build --platform linux/amd64 \
        -t "${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}" \
        -f Dockerfile.local .

    echo "   -> ⬆️ [Step 3] 推送镜像..."
    docker push "${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}"

    echo "✅ 前端处理完成！"
}

# ========================================================
# 主逻辑
# ========================================================

case "$MODE" in
    "backend")
        build_backend
        ;;
    "frontend")
        build_frontend
        ;;
    "all")
        # 串行执行，确保日志清晰
        build_backend
        build_frontend
        ;;
    "parallel")
        # 并行执行，提高效率
        echo "⚡️ 启动并行构建..."
        build_backend &
        PID_BACKEND=$!
        
        build_frontend &
        PID_FRONTEND=$!
        
        # 等待所有任务完成
        wait $PID_BACKEND
        CODE_BACKEND=$?
        wait $PID_FRONTEND
        CODE_FRONTEND=$?
        
        if [ $CODE_BACKEND -eq 0 ] && [ $CODE_FRONTEND -eq 0 ]; then
             echo "✅ 并行构建全部成功！"
        else
             echo "❌ 并行构建存在失败任务。"
             exit 1
        fi
        ;;
    *)
        echo "❌ 未知模式: $MODE"
        echo "请运行 ./build_publish_fast.sh help 查看详细说明"
        exit 1
        ;;
esac

# ========================================================
# 结束摘要
# ========================================================
echo ""
echo "========================================================"
echo "🎉 任务执行结束！"
echo "--------------------------------------------------------"
if [[ "$MODE" == "all" || "$MODE" == "backend" || "$MODE" == "parallel" ]]; then
    echo "后端镜像: ${REGISTRY}/${NAMESPACE}/ruoyi-vue-pro:${VERSION}"
fi
if [[ "$MODE" == "all" || "$MODE" == "frontend" || "$MODE" == "parallel" ]]; then
    echo "前端镜像: ${REGISTRY}/${NAMESPACE}/yudao-ui-admin-vue3:${VERSION}"
fi
echo "========================================================"
