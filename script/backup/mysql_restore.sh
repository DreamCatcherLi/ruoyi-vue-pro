#!/bin/bash

# MySQL Docker Compose 恢复脚本
# 用于从备份文件恢复数据库

set -e

# ==================== 配置区域 ====================
# 加载环境变量
ENV_FILE_PATH="${PROJECT_ROOT}/script/docker/.env"
if [ -f "$ENV_FILE_PATH" ]; then
    export $(cat "$ENV_FILE_PATH" | grep -v '^#' | xargs)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
DOCKER_COMPOSE_PATH="${PROJECT_ROOT}/script/docker/docker-compose.yml"

# 数据库配置 (从 .env 文件读取默认值)
DB_NAME="${MYSQL_DATABASE:-ruoyi-vue-pro}"
DB_USER="root"
DB_PASS="${MYSQL_ROOT_PASSWORD:-mysqlQWER0011!}"
DB_HOST="localhost"
DB_PORT="3307"

# ==================== 函数定义 ====================

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

check_docker_compose() {
    log_message "INFO" "检查 Docker Compose 服务状态"
    
    if ! docker compose -f "$DOCKER_COMPOSE_PATH" ps | grep -q "yudao-mysql"; then
        log_message "ERROR" "MySQL 容器未找到，请确保 Docker Compose 已启动"
        exit 1
    fi
    
    if ! docker compose -f "$DOCKER_COMPOSE_PATH" exec mysql mysqladmin ping -h localhost -u"$DB_USER" -p"$DB_PASS" --silent; then
        log_message "ERROR" "无法连接到 MySQL 数据库，请检查连接信息"
        exit 1
    fi
    
    log_message "INFO" "MySQL 连接正常"
}

restore_from_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_message "ERROR" "备份文件不存在: $backup_file"
        exit 1
    fi
    
    log_message "INFO" "开始从备份文件恢复: $backup_file"
    
    # 如果是压缩文件，则先解压
    local temp_file
    if [[ "$backup_file" == *.gz ]]; then
        temp_file="/tmp/restore_$(basename "$backup_file" .gz)"
        log_message "INFO" "解压备份文件..."
        gunzip -c "$backup_file" > "$temp_file"
    else
        temp_file="$backup_file"
    fi
    
    # 检查数据库是否存在，如果不存在则创建
    if ! docker compose -f "$DOCKER_COMPOSE_PATH" exec mysql mysql -u"$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;"; then
        log_message "INFO" "数据库 $DB_NAME 不存在，正在创建..."
        docker compose -f "$DOCKER_COMPOSE_PATH" exec mysql mysql -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    fi
    
    # 执行恢复操作
    log_message "INFO" "开始导入数据..."
    docker compose -f "$DOCKER_COMPOSE_PATH" exec -T mysql mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$temp_file"
    
    # 清理临时文件
    if [[ "$backup_file" == *.gz ]]; then
        rm -f "$temp_file"
    fi
    
    log_message "INFO" "数据库恢复完成: $DB_NAME"
}

list_available_backups() {
    local backup_dir="/opt/yudao/backups/mysql"
    log_message "INFO" "可用的备份文件:"
    
    if [ -d "$backup_dir/daily" ]; then
        echo "Daily backups:"
        ls -la "$backup_dir/daily/" 2>/dev/null || echo "  No daily backups found"
    fi
    
    if [ -d "$backup_dir/weekly" ]; then
        echo "Weekly backups:"
        ls -la "$backup_dir/weekly/" 2>/dev/null || echo "  No weekly backups found"
    fi
    
    if [ -d "$backup_dir/monthly" ]; then
        echo "Monthly backups:"
        ls -la "$backup_dir/monthly/" 2>/dev/null || echo "  No monthly backups found"
    fi
}

show_help() {
    echo "用法: $0 [选项] [备份文件路径]"
    echo ""
    echo "选项:"
    echo "  -h, --help           显示此帮助信息"
    echo "  -l, --list           列出所有可用的备份文件"
    echo "  -f, --file FILE      指定要恢复的备份文件"
    echo ""
    echo "示例:"
    echo "  $0 -f /opt/backups/mysql/daily/ruoyi-vue-pro_20231201_120000.sql.gz"
    echo "  $0 --list"
}

# ==================== 主流程 ====================

if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_available_backups
            exit 0
            ;;
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    log_message "ERROR" "必须指定备份文件路径"
    show_help
    exit 1
fi

log_message "INFO" "开始数据库恢复流程"
check_docker_compose
restore_from_backup "$BACKUP_FILE"
log_message "INFO" "数据库恢复完成"