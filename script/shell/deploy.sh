#!/bin/bash

# 芋道系统 Docker 镜像部署脚本
# 作者: DevOps Engineer
# 日期: $(date +%Y-%m-%d)

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEPLOY_ROOT="/opt/yudao/yudao-deployment"
log_info "SCRIPT_DIR目录: $SCRIPT_DIR"
log_info "PROJECT_ROOT目录: $PROJECT_ROOT"
log_info "DEPLOY_ROOT目录: $DEPLOY_ROOT"

# 加载 .env 文件
if [ -f "$DEPLOY_ROOT/docker/.env" ]; then
    export $(cat "$DEPLOY_ROOT/docker/.env" | grep -v '^#' | xargs)
fi

# 部署脚本文件到指定目录
deploy_scripts() {
    log_info "部署脚本文件到 /opt/yudao/yudao-deployment 目录..."

    # 创建部署目录
    sudo mkdir -p /opt/yudao/yudao-deployment
    
    # 复制 script/docker 目录
    if [ -d "$PROJECT_ROOT/script/docker" ]; then
        log_info "复制 script/docker 目录到 /opt/yudao/yudao-deployment/docker"
        sudo cp -r "$PROJECT_ROOT/script/docker" /opt/yudao/yudao-deployment/
    else
        log_warn "目录不存在: $PROJECT_ROOT/script/docker"
    fi
    
    # 复制 script/shell 目录（除了当前脚本）
    if [ -d "$PROJECT_ROOT/script/shell" ]; then
        log_info "复制 script/shell 目录到 /opt/yudao/yudao-deployment/shell"
        # 创建临时目录用于复制，排除当前脚本
        TEMP_SHELL_DIR=$(mktemp -d)
        cp -r "$PROJECT_ROOT/script/shell"/* "$TEMP_SHELL_DIR/" 2>/dev/null || true
        # 将当前脚本备份到临时目录（如果需要保留）
        cp "$SCRIPT_DIR/deploy.sh" "$TEMP_SHELL_DIR/deploy.sh.backup" 2>/dev/null || true
        sudo cp -r "$TEMP_SHELL_DIR"/. /opt/yudao/yudao-deployment/shell/
        rm -rf "$TEMP_SHELL_DIR"
    else
        log_warn "目录不存在: $PROJECT_ROOT/script/shell"
    fi
    
    # 设置部署目录权限
    sudo chown -R $(whoami):$(whoami) /opt/yudao/yudao-deployment 2>/dev/null || true
    sudo chmod -R 755 /opt/yudao/yudao-deployment 2>/dev/null || true
    
    log_info "部署脚本文件完成"
}

# 创建必要的目录并设置权限
setup_directories() {
    log_info "设置目录结构和权限..."

    # 创建日志目录
    sudo mkdir -p /var/log/yudao/ruoyi-vue-pro
    
    # 设置目录权限，确保当前用户和Docker都能访问
    sudo chown -R $(whoami):$(whoami) /var/log/yudao/ 2>/dev/null || true
    
    # 确保目录有适当的读写权限
    sudo chmod -R 755 /var/log/yudao/ 2>/dev/null || true
    
    # 为日志目录设置更宽松的权限，让Docker容器可以写入
    sudo chmod 777 /var/log/yudao/ruoyi-vue-pro 2>/dev/null || true
    
    log_info "目录结构和权限设置完成"
}

# 检查必要工具
check_prerequisites() {
    log_info "检查必要工具..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi

    log_info "所有必要工具都已安装"
}

# 拉取最新镜像
pull_images() {
    log_info "拉取最新镜像..."
    
    # 从环境变量或默认值获取镜像名称
    BACKEND_IMAGE=${BACKEND_IMAGE:-registry.cn-beijing.aliyuncs.com/liam_test/ruoyi-vue-pro:latest}
    FRONTEND_IMAGE=${FRONTEND_IMAGE:-registry.cn-beijing.aliyuncs.com/liam_test/yudao-ui-admin-vue3:latest}
    
    log_info "拉取后端服务镜像: $BACKEND_IMAGE"
    docker pull "$BACKEND_IMAGE"
    
    log_info "拉取前端服务镜像: $FRONTEND_IMAGE"
    docker pull "$FRONTEND_IMAGE"
    
    log_info "镜像拉取完成"
}

# 构建并启动服务
start_services() {
    log_info "拉取镜像并启动所有服务..."
    
    # 切换到部署目录，确保能找到 docker-compose.yml
    cd "$DEPLOY_ROOT/docker"
    
    # 拉取最新的镜像
    pull_images
    
    # 启动服务
    docker compose up -d
    
    if [ $? -ne 0 ]; then
        log_error "服务启动失败"
        exit 1
    fi
    
    log_info "所有服务已启动"
    cd "$PROJECT_ROOT"
}

# 检查服务状态
check_services() {
    log_info "检查服务状态..."
    
    sleep 10  # 等待服务启动
    
    # 切换到 docker-compose.yml 所在目录
    cd "$DEPLOY_ROOT/docker"
    
    # 检查所有容器状态
    docker compose ps
    
    # 检查关键服务是否健康 - 使用表格格式并解析
    MYSQL_STATUS=$(docker compose ps mysql --format "table {{.Status}}" | tail -n +2 | xargs || echo "not running")
    REDIS_STATUS=$(docker compose ps redis --format "table {{.Status}}" | tail -n +2 | xargs || echo "not running")
    SERVER_STATUS=$(docker compose ps server --format "table {{.Status}}" | tail -n +2 | xargs || echo "not running")
    FRONTEND_STATUS=$(docker compose ps frontend --format "table {{.Status}}" | tail -n +2 | xargs || echo "not running")
    
    # 简化状态判断，只要包含"Up"就认为是在运行
    MYSQL_RUNNING=$(echo "$MYSQL_STATUS" | grep -q "Up" && echo "running" || echo "stopped")
    REDIS_RUNNING=$(echo "$REDIS_STATUS" | grep -q "Up" && echo "running" || echo "stopped")
    SERVER_RUNNING=$(echo "$SERVER_STATUS" | grep -q "Up" && echo "running" || echo "stopped")
    FRONTEND_RUNNING=$(echo "$FRONTEND_STATUS" | grep -q "Up" && echo "running" || echo "stopped")
    
    log_info "服务状态:"
    echo "  MySQL: $MYSQL_STATUS ($MYSQL_RUNNING)"
    echo "  Redis: $REDIS_STATUS ($REDIS_RUNNING)" 
    echo "  Server: $SERVER_STATUS ($SERVER_RUNNING)"
    echo "  Frontend: $FRONTEND_STATUS ($FRONTEND_RUNNING)"
    
    if [[ "$MYSQL_RUNNING" == "running" ]] && [[ "$REDIS_RUNNING" == "running" ]] && [[ "$SERVER_RUNNING" == "running" ]]; then
        log_info "所有关键服务都在运行中"
        log_info "系统访问地址: http://localhost"
        log_info "后端API地址: http://localhost:48080"
    else
        log_warn "部分服务可能存在问题，请检查日志"
    fi
    
    cd "$PROJECT_ROOT"
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 [选项]"
    echo "选项:"
    echo "  copy      - 部署脚本文件到 /opt/yudao/yudao-deployment 目录"
    echo "  setup     - 设置目录结构和权限"
    echo "  pull      - 拉取最新镜像"
    echo "  start     - 拉取镜像并启动服务"
    echo "  stop      - 停止所有服务"
    echo "  restart   - 重启所有服务"
    echo "  logs      - 查看服务日志"
    echo "  status    - 查看服务状态"
    echo "  cleanup   - 清理所有容器和数据"
    echo "  help      - 显示此帮助信息"
}

# 停止服务
stop_services() {
    log_info "停止所有服务..."
    
    cd "$DEPLOY_ROOT/docker"
    docker compose down
    log_info "所有服务已停止"
    cd "$PROJECT_ROOT"
}

# 重启服务
restart_services() {
    log_info "重启所有服务..."
    
    cd "$DEPLOY_ROOT/docker"
    docker compose restart
    log_info "所有服务已重启"
    cd "$PROJECT_ROOT"
}

# 查看日志
show_logs() {
    log_info "显示服务日志 (按 Ctrl+C 退出)..."
    
    cd "$DEPLOY_ROOT/docker"
    docker compose logs -f
    cd "$PROJECT_ROOT"
}

# 查看状态
show_status() {
    log_info "当前服务状态:"
    
    cd "$DEPLOY_ROOT/docker"
    docker compose ps
    cd "$PROJECT_ROOT"
}

# 清理服务
cleanup() {
    log_warn "警告: 此操作将删除所有容器、网络和卷，数据将永久丢失!"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "清理所有服务和数据..."
        
        cd "$DEPLOY_ROOT/docker"
        docker compose down -v --remove-orphans
        log_info "清理完成"
        cd "$PROJECT_ROOT"
    else
        log_info "取消清理操作"
    fi
}

# 主函数
main() {
    case "${1:-help}" in
        "copy")
            deploy_scripts
            ;;
        "setup")
            setup_directories
            ;;
        "pull")
            pull_images
            ;;
        "start")
            setup_directories
            check_prerequisites
            start_services
            check_services
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "logs")
            show_logs
            ;;
        "status")
            show_status
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# 执行主函数
main "$@"