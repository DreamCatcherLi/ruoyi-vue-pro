#!/bin/bash

# MySQL 备份监控脚本
# 用于检查备份状态和磁盘空间使用情况

set -e

# ==================== 配置区域 ====================
BACKUP_DIR="/opt/yudao/backups/mysql"
THRESHOLD_CRITICAL=85  # 磁盘使用率阈值（百分比）
THRESHOLD_WARNING=75   # 警告阈值
LOG_FILE="${BACKUP_DIR}/monitor.log"

# 邮件配置（可选）
ENABLE_EMAIL=false
EMAIL_ADDRESS="admin@example.com"

# ==================== 函数定义 ====================

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

check_disk_space() {
    log_message "INFO" "检查磁盘空间使用情况"
    
    local disk_usage=$(df "$BACKUP_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    
    log_message "INFO" "备份目录总大小: $total_size"
    log_message "INFO" "磁盘使用率: ${disk_usage}%"
    
    if [ "$disk_usage" -ge "$THRESHOLD_CRITICAL" ]; then
        log_message "CRITICAL" "磁盘使用率超过临界阈值 ($THRESHOLD_CRITICAL%)！需要立即清理！"
        send_alert "CRITICAL: Disk usage at ${disk_usage}% - Immediate action required!"
    elif [ "$disk_usage" -ge "$THRESHOLD_WARNING" ]; then
        log_message "WARNING" "磁盘使用率超过警告阈值 ($THRESHOLD_WARNING%)"
        send_alert "WARNING: Disk usage at ${disk_usage}% - Consider cleaning up backups"
    else
        log_message "INFO" "磁盘使用率正常"
    fi
}

check_latest_backup() {
    log_message "INFO" "检查最新备份状态"
    
    local latest_backup=$(find "$BACKUP_DIR/daily" -name "*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_backup" ]; then
        local backup_time=$(stat -c %Y "$latest_backup")
        local current_time=$(date +%s)
        local hours_diff=$(( (current_time - backup_time) / 3600 ))
        
        log_message "INFO" "最新备份文件: $(basename "$latest_backup")"
        log_message "INFO" "备份时间: $(date -d "@$backup_time" "+%Y-%m-%d %H:%M:%S")"
        log_message "INFO" "距离上次备份: ${hours_diff}小时"
        
        if [ "$hours_diff" -gt 24 ]; then
            log_message "WARNING" "超过24小时未进行备份！"
            send_alert "WARNING: No backup in last 24 hours - Latest backup was ${hours_diff} hours ago"
        else
            log_message "INFO" "备份频率正常"
        fi
    else
        log_message "WARNING" "未找到备份文件！"
        send_alert "WARNING: No backup files found in $BACKUP_DIR/daily"
    fi
}

send_alert() {
    local message="$1"
    log_message "ALERT" "$message"
    
    if [ "$ENABLE_EMAIL" = true ]; then
        local subject="Backup Alert - $(hostname)"
        echo "$message" | mail -s "$subject" "$EMAIL_ADDRESS"
    fi
}

generate_report() {
    log_message "INFO" "生成备份报告"
    
    echo "==================== 备份报告 ====================" >> "$LOG_FILE"
    echo "报告时间: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "磁盘使用情况:" >> "$LOG_FILE"
    df -h "$BACKUP_DIR" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "备份目录大小:" >> "$LOG_FILE"
    du -sh "$BACKUP_DIR" 2>/dev/null >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "备份文件统计:" >> "$LOG_FILE"
    echo "每日备份数量: $(find "$BACKUP_DIR/daily" -name "*.sql.gz" -type f | wc -l)" >> "$LOG_FILE"
    echo "每周备份数量: $(find "$BACKUP_DIR/weekly" -name "*.sql.gz" -type f | wc -l)" >> "$LOG_FILE"
    echo "每月备份数量: $(find "$BACKUP_DIR/monthly" -name "*.sql.gz" -type f | wc -l)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "最近5个备份文件:" >> "$LOG_FILE"
    find "$BACKUP_DIR/daily" -name "*.sql.gz" -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -nr | head -5 >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    echo "==================================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

cleanup_old_logs() {
    log_message "INFO" "清理旧的日志文件"
    find "$BACKUP_DIR" -name "*.log" -type f -mtime +30 -delete
}

# ==================== 主流程 ====================

main() {
    log_message "INFO" "开始执行备份监控任务"
    
    check_disk_space
    check_latest_backup
    generate_report
    cleanup_old_logs
    
    log_message "INFO" "备份监控任务完成"
}

main "$@"