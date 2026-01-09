#!/bin/bash

# 芋道系统 Docker 部署脚本
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

# 检查必要工具
check_prerequisites() {
    log_info "检查必要工具..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi

    log_info "所有必要工具都已安装"
}

# 编译后端项目
build_backend() {
    log_info "开始编译后端项目..."
    
    cd yudao-server
    
    if [ ! -f "pom.xml" ]; then
        log_error "yudao-server 目录中未找到 pom.xml 文件"
        exit 1
    fi
    
    mvn clean package -DskipTests
    
    if [ $? -ne 0 ]; then
        log_error "后端项目编译失败"
        exit 1
    fi
    
    log_info "后端项目编译完成"
    cd ..
}

# 编译前端项目
build_frontend() {
    log_info "检查前端项目..."
    
    if [ ! -d "yudao-ui/yudao-ui-admin-vue3" ]; then
        log_error "前端项目目录不存在"
        exit 1
    fi
    
    cd yudao-ui/yudao-ui-admin-vue3
    
    # 检查是否有package.json
    if [ ! -f "package.json" ]; then
        log_error "前端项目中未找到 package.json 文件"
        exit 1
    fi
    
    # 安装依赖（使用国内镜像）
    npm install --registry https://registry.npmmirror.com
    
    if [ $? -ne 0 ]; then
        log_error "前端项目依赖安装失败"
        exit 1
    fi
    
    log_info "前端项目依赖安装完成"
    cd ../../..
}

# 构建并启动服务
start_services() {
    log_info "构建并启动所有服务..."
    
    # 构建并启动服务
    docker-compose up -d --build
    
    if [ $? -ne 0 ]; then
        log_error "服务启动失败"
        exit 1
    fi
    
    log_info "所有服务已启动"
}

# 检查服务状态
check_services() {
    log_info "检查服务状态..."
    
    sleep 10  # 等待服务启动
    
    # 检查所有容器状态
    docker-compose ps
    
    # 检查关键服务是否健康
    MYSQL_STATUS=$(docker-compose ps mysql --format json | jq -r '.State' 2>/dev/null || echo "unknown")
    REDIS_STATUS=$(docker-compose ps redis --format json | jq -r '.State' 2>/dev/null || echo "unknown")
    SERVER_STATUS=$(docker-compose ps server --format json | jq -r '.State' 2>/dev/null || echo "unknown")
    FRONTEND_STATUS=$(docker-compose ps frontend --format json | jq -r '.State' 2>/dev/null || echo "unknown")
    
    log_info "服务状态:"
    echo "  MySQL: $MYSQL_STATUS"
    echo "  Redis: $REDIS_STATUS" 
    echo "  Server: $SERVER_STATUS"
    echo "  Frontend: $FRONTEND_STATUS"
    
    if [[ "$MYSQL_STATUS" == "running" ]] && [[ "$REDIS_STATUS" == "running" ]] && [[ "$SERVER_STATUS" == "running" ]]; then
        log_info "所有关键服务都在运行中"
        log_info "系统访问地址: http://localhost"
        log_info "后端API地址: http://localhost:48080"
    else
        log_warn "部分服务可能存在问题，请检查日志"
    fi
}

# 显示使用说明
show_usage() {
    echo "使用方法: $0 [选项]"
    echo "选项:"
    echo "  build     - 编译项目并启动服务"
    echo "  start     - 启动已构建的服务"
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
    docker-compose down
    log_info "所有服务已停止"
}

# 重启服务
restart_services() {
    log_info "重启所有服务..."
    docker-compose restart
    log_info "所有服务已重启"
}

# 查看日志
show_logs() {
    log_info "显示服务日志 (按 Ctrl+C 退出)..."
    docker-compose logs -f
}

# 查看状态
show_status() {
    log_info "当前服务状态:"
    docker-compose ps
}

# 清理服务
cleanup() {
    log_warn "警告: 此操作将删除所有容器、网络和卷，数据将永久丢失!"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "清理所有服务和数据..."
        docker-compose down -v --remove-orphans
        log_info "清理完成"
    else
        log_info "取消清理操作"
    fi
}

# 主函数
main() {
    case "${1:-help}" in
        "build")
            check_prerequisites
            build_backend
            build_frontend
            start_services
            check_services
            ;;
        "start")
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