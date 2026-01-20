#!/bin/bash

# 设置自动备份 Cron 任务

set -e

# ==================== 配置区域 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

BACKUP_SCRIPT="${SCRIPT_DIR}/mysql_backup.sh"
MONITOR_SCRIPT="${SCRIPT_DIR}/backup_monitor.sh"
LOG_DIR="/opt/yudao/backups/mysql"

# ==================== 函数定义 ====================

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

setup_directories() {
    log_message "INFO" "创建必要的目录"
    sudo mkdir -p "$LOG_DIR"
    sudo chmod 755 "$LOG_DIR"
    
    # 创建日志目录（如果不存在）
    sudo touch "$LOG_DIR/backup.log"
    sudo chmod 644 "$LOG_DIR/backup.log"
}

setup_permissions() {
    log_message "INFO" "设置脚本权限"
    
    chmod +x "$BACKUP_SCRIPT"
    chmod +x "$MONITOR_SCRIPT"
    chmod +x "${SCRIPT_DIR}/setup_cron.sh"
    
    # 尝试获取当前用户ID和组ID
    CURRENT_USER=$(whoami)
    CURRENT_GROUP=$(id -gn)
    
    # 如果脚本在 /opt 下，可能需要sudo权限
    if [[ "$BACKUP_SCRIPT" =~ ^/opt/ ]]; then
        sudo chown "$CURRENT_USER:$CURRENT_GROUP" "$BACKUP_SCRIPT"
        sudo chown "$CURRENT_USER:$CURRENT_GROUP" "$MONITOR_SCRIPT"
    fi
}

create_crontab_entry() {
    log_message "INFO" "创建 Cron 任务"
    
    # 创建临时 crontab 文件
    TEMP_CRON=$(mktemp)
    
    # 获取当前用户的 crontab（如果存在）
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    
    # 检查是否已存在类似的备份任务
    if grep -q "mysql_backup.sh" "$TEMP_CRON" 2>/dev/null; then
        log_message "INFO" "检测到已存在的备份任务，跳过添加"
    else
        # 添加新的备份任务（每天凌晨2点执行）
        echo "0 2 * * * $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1" >> "$TEMP_CRON"
        log_message "INFO" "添加每日备份任务: 0 2 * * *"
    fi
    
    # 检查是否已存在监控任务
    if grep -q "backup_monitor.sh" "$TEMP_CRON" 2>/dev/null; then
        log_message "INFO" "检测到已存在的监控任务，跳过添加"
    else
        # 添加监控任务（每天早上6点执行）
        echo "0 6 * * * $MONITOR_SCRIPT >> $LOG_DIR/monitor.log 2>&1" >> "$TEMP_CRON"
        log_message "INFO" "添加每日监控任务: 0 6 * * *"
    fi
    
    # 安装更新后的 crontab
    crontab "$TEMP_CRON"
    
    # 清理临时文件
    rm "$TEMP_CRON"
    
    log_message "INFO" "Cron 任务已更新"
}

show_current_crontab() {
    log_message "INFO" "当前 Cron 任务列表:"
    crontab -l
}

validate_setup() {
    log_message "INFO" "验证备份设置"
    
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_message "ERROR" "备份脚本不存在: $BACKUP_SCRIPT"
        exit 1
    fi
    
    if [ ! -f "$MONITOR_SCRIPT" ]; then
        log_message "ERROR" "监控脚本不存在: $MONITOR_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$BACKUP_SCRIPT" ]; then
        log_message "ERROR" "备份脚本没有执行权限: $BACKUP_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$MONITOR_SCRIPT" ]; then
        log_message "ERROR" "监控脚本没有执行权限: $MONITOR_SCRIPT"
        exit 1
    fi
    
    log_message "INFO" "所有文件验证通过"
    
    # 测试脚本语法
    if bash -n "$BACKUP_SCRIPT"; then
        log_message "INFO" "备份脚本语法正确"
    else
        log_message "ERROR" "备份脚本语法错误"
        exit 1
    fi
    
    if bash -n "$MONITOR_SCRIPT"; then
        log_message "INFO" "监控脚本语法正确"
    else
        log_message "ERROR" "监控脚本语法错误"
        exit 1
    fi
}

show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help           显示此帮助信息"
    echo "  -v, --validate       验证备份设置"
    echo "  -s, --setup          完整设置备份环境"
    echo "  -l, --list           列出当前 cron 任务"
    echo "  -r, --remove         移除备份相关的 cron 任务"
    echo ""
    echo "示例:"
    echo "  $0 --setup          # 完整设置备份环境"
    echo "  $0 --validate       # 验证备份设置"
    echo "  $0 --list           # 查看当前 cron 任务"
}

remove_cron_entries() {
    log_message "INFO" "移除备份相关的 Cron 任务"
    
    # 创建临时 crontab 文件
    TEMP_CRON=$(mktemp)
    
    # 获取当前用户的 crontab 并过滤掉备份相关的任务
    crontab -l > "$TEMP_CRON" 2>/dev/null || true
    
    # 移除备份和监控任务
    sed -i '/mysql_backup.sh/d' "$TEMP_CRON"
    sed -i '/backup_monitor.sh/d' "$TEMP_CRON"
    
    # 安装更新后的 crontab
    crontab "$TEMP_CRON"
    
    # 清理临时文件
    rm "$TEMP_CRON"
    
    log_message "INFO" "备份相关的 Cron 任务已移除"
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
        -v|--validate)
            validate_setup
            exit 0
            ;;
        -s|--setup)
            setup_directories
            setup_permissions
            validate_setup
            create_crontab_entry
            show_current_crontab
            log_message "INFO" "备份环境设置完成！"
            exit 0
            ;;
        -l|--list)
            show_current_crontab
            exit 0
            ;;
        -r|--remove)
            remove_cron_entries
            exit 0
            ;;
        *)
            log_message "ERROR" "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done