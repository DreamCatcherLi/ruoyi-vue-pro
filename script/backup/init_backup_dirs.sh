#!/bin/bash

# 初始化备份目录结构
# 用于创建 /opt/yudao/backups/mysql 目录及其子目录

set -e

BACKUP_BASE_DIR="/opt/yudao/backups"
MYSQL_BACKUP_DIR="$BACKUP_BASE_DIR/mysql"
LOG_FILE="$MYSQL_BACKUP_DIR/backup.log"

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

create_directories() {
    log_message "INFO" "创建备份目录结构: $MYSQL_BACKUP_DIR"
    
    sudo mkdir -p "$MYSQL_BACKUP_DIR"/{daily,weekly,monthly,temp}
    
    # 设置目录权限
    sudo chmod -R 755 "$MYSQL_BACKUP_DIR"
    sudo chmod 755 "$MYSQL_BACKUP_DIR"/{daily,weekly,monthly,temp}
    
    # 创建日志文件
    sudo touch "$LOG_FILE"
    sudo chmod 644 "$LOG_FILE"
    
    log_message "INFO" "备份目录结构创建完成"
    log_message "INFO" "目录路径: $MYSQL_BACKUP_DIR"
}

verify_setup() {
    log_message "INFO" "验证目录设置"
    
    if [ -d "$MYSQL_BACKUP_DIR" ]; then
        log_message "INFO" "✓ 主备份目录存在: $MYSQL_BACKUP_DIR"
    else
        log_message "ERROR" "✗ 主备份目录不存在: $MYSQL_BACKUP_DIR"
        exit 1
    fi
    
    # 检查子目录
    for subdir in daily weekly monthly temp; do
        if [ -d "$MYSQL_BACKUP_DIR/$subdir" ]; then
            log_message "INFO" "✓ 子目录存在: $MYSQL_BACKUP_DIR/$subdir"
        else
            log_message "ERROR" "✗ 子目录不存在: $MYSQL_BACKUP_DIR/$subdir"
            exit 1
        fi
    done
    
    # 检查日志文件
    if [ -f "$LOG_FILE" ]; then
        log_message "INFO" "✓ 日志文件存在: $LOG_FILE"
    else
        log_message "ERROR" "✗ 日志文件不存在: $LOG_FILE"
        exit 1
    fi
    
    log_message "INFO" "目录结构验证通过"
}

show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "初始化备份目录结构脚本"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --create   创建备份目录结构"
    echo "  -v, --verify   验证现有目录结构"
    echo ""
    echo "示例:"
    echo "  $0 --create    # 创建备份目录结构"
    echo "  $0 --verify    # 验证目录结构"
}

# 主流程
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
        -c|--create)
            create_directories
            exit 0
            ;;
        -v|--verify)
            verify_setup
            exit 0
            ;;
        *)
            log_message "ERROR" "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done