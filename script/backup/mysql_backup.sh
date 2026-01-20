#!/bin/bash

# MySQL Docker Compose 备份脚本
# 用于定期备份 Docker Compose 中运行的 MySQL 数据库

set -e

# ==================== 配置区域 ====================
# 加载环境变量
ENV_FILE_PATH="${PROJECT_ROOT}/script/docker/.env"
if [ -f "$ENV_FILE_PATH" ]; then
    export $(cat "$ENV_FILE_PATH" | grep -v '^#' | xargs)
fi

# 基础路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
DOCKER_COMPOSE_PATH="${PROJECT_ROOT}/script/docker/docker-compose.yml"
BACKUP_DIR="/opt/yudao/backups/mysql"
DATE=$(date +"%Y%m%d_%H%M%S")

# 数据库配置 (从 .env 文件读取默认值)
DB_NAME="${MYSQL_DATABASE:-ruoyi-vue-pro}"
DB_USER="root"
DB_PASS="${MYSQL_ROOT_PASSWORD:-123456}"
DB_HOST="localhost"
DB_PORT="3307"  # 与 docker-compose.yml 中的映射端口一致

# 备份保留策略
DAYS_TO_KEEP=7
WEEKS_TO_KEEP=4
MONTHS_TO_KEEP=6

# 阿里云OSS配置
OSS_ENABLED=${OSS_ENABLED:-false}
OSS_BUCKET_NAME=${OSS_BUCKET_NAME:-""}
OSS_ENDPOINT=${OSS_ENDPOINT:-"oss-cn-hangzhou.aliyuncs.com"}

# 邮件通知配置 (可选)
ENABLE_EMAIL=${ENABLE_EMAIL:-false}
EMAIL_ADDRESS=${EMAIL_ADDRESS:-"admin@example.com"}

# 日志配置
LOG_FILE="${BACKUP_DIR}/backup.log"

# ==================== 函数定义 ====================

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

create_directories() {
    log_message "INFO" "创建备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly" "$BACKUP_DIR/temp"
    
    # 设置适当的权限
    chmod 755 "$BACKUP_DIR"
    chmod 755 "$BACKUP_DIR/daily"
    chmod 755 "$BACKUP_DIR/weekly" 
    chmod 755 "$BACKUP_DIR/monthly"
    chmod 755 "$BACKUP_DIR/temp"
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

perform_backup() {
    log_message "INFO" "开始备份数据库: $DB_NAME"
    
    local backup_file="${BACKUP_DIR}/temp/${DB_NAME}_${DATE}.sql"
    local compressed_file="${BACKUP_DIR}/daily/${DB_NAME}_${DATE}.sql.gz"
    
    # 执行数据库备份
    docker compose -f "$DOCKER_COMPOSE_PATH" exec mysql \
        mysqldump -u"$DB_USER" -p"$DB_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        --all \
        --ignore-table=mysql.event \
        --hex-blob \
        --skip-lock-tables \
        --add-drop-database \
        --add-drop-table \
        --add-locks \
        --comments \
        --create-options \
        --dump-date \
        --events \
        --extended-insert \
        --flush-privileges \
        --order-by-primary \
        --quick \
        --quote-names \
        --set-charset \
        --triggers \
        --disable-keys \
        --enable-closures \
        --force \
        --host=localhost \
        --max_allowed_packet=1G \
        --net_buffer_length=1M \
        --compress \
        "$DB_NAME" > "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "数据库导出成功: $backup_file"
        
        # 压缩备份文件
        gzip "$backup_file"
        mv "${backup_file}.gz" "$compressed_file"
        
        log_message "INFO" "备份文件已压缩: $compressed_file"
        log_message "INFO" "备份完成: $(du -h "$compressed_file" | cut -f1)"
    else
        log_message "ERROR" "数据库备份失败"
        rm -f "$backup_file"
        exit 1
    fi
}

cleanup_temp_files() {
    log_message "INFO" "清理临时文件"
    rm -rf "$BACKUP_DIR/temp/*"
}

rotate_backups() {
    log_message "INFO" "开始执行备份轮转策略"
    
    # 删除超过保留期限的日常备份
    find "$BACKUP_DIR/daily" -name "*.sql.gz" -type f -mtime +$DAYS_TO_KEEP -delete
    log_message "INFO" "删除 $DAYS_TO_KEEP 天前的日常备份"
    
    # 每周日执行周备份 (保留最近4周)
    if [ $(date +%u) -eq 7 ]; then
        local weekly_backup="${BACKUP_DIR}/weekly/${DB_NAME}_week$(date +%U)_${DATE}.sql.gz"
        local latest_daily=$(ls -t "$BACKUP_DIR/daily"/*.sql.gz 2>/dev/null | head -n1)
        if [ -n "$latest_daily" ]; then
            cp "$latest_daily" "$weekly_backup"
            log_message "INFO" "创建周备份: $weekly_backup"
        fi
        
        # 删除超过保留期限的周备份
        find "$BACKUP_DIR/weekly" -name "*.sql.gz" -type f -mtime +$((WEEKS_TO_KEEP * 7)) -delete
    fi
    
    # 每月第一天执行月备份 (保留最近6个月)
    if [ $(date +%-d) -eq 1 ]; then
        local monthly_backup="${BACKUP_DIR}/monthly/${DB_NAME}_month$(date +%m)_${DATE}.sql.gz"
        local latest_daily=$(ls -t "$BACKUP_DIR/daily"/*.sql.gz 2>/dev/null | head -n1)
        if [ -n "$latest_daily" ]; then
            cp "$latest_daily" "$monthly_backup"
            log_message "INFO" "创建月备份: $monthly_backup"
        fi
        
        # 删除超过保留期限的月备份
        find "$BACKUP_DIR/monthly" -name "*.sql.gz" -type f -mtime +$((MONTHS_TO_KEEP * 30)) -delete
    fi
}

send_notification() {
    if [ "$ENABLE_EMAIL" = true ]; then
        local subject="MySQL Backup Status - $(hostname)"
        local body="MySQL Database Backup completed on $(date)\n\n"
        body+="Status: SUCCESS\n"
        body+="Database: $DB_NAME\n"
        body+="Backup Size: $(du -h "${BACKUP_DIR}/daily/${DB_NAME}_${DATE}.sql.gz" | cut -f1)\n"
        body+="Backup Location: ${BACKUP_DIR}/daily/${DB_NAME}_${DATE}.sql.gz\n"
        
        echo -e "$body" | mail -s "$subject" "$EMAIL_ADDRESS"
    fi
}

upload_to_remote() {
    if [ "$OSS_ENABLED" = true ] && [ -n "$OSS_BUCKET_NAME" ]; then
        local compressed_file="${BACKUP_DIR}/daily/${DB_NAME}_${DATE}.sql.gz"
        
        if command -v ossutil &> /dev/null; then
            local oss_path="mysql-backups/${DB_NAME}/${DATE}/$(basename "$compressed_file")"
            
            log_message "INFO" "上传备份到阿里云OSS: oss://$OSS_BUCKET_NAME/$oss_path"
            
            # 上传到OSS
            if ossutil cp "$compressed_file" "oss://$OSS_BUCKET_NAME/$oss_path" -e "$OSS_ENDPOINT"; then
                log_message "INFO" "成功上传到阿里云OSS"
                
                # 验证上传
                if ossutil stat "oss://$OSS_BUCKET_NAME/$oss_path" > /dev/null 2>&1; then
                    log_message "INFO" "OSS 文件验证成功"
                else
                    log_message "WARNING" "OSS 文件验证失败"
                fi
            else
                log_message "ERROR" "上传到阿里云OSS失败"
            fi
        else
            log_message "WARNING" "未安装 ossutil，跳过远程备份"
        fi
    else
        log_message "INFO" "OSS备份未启用，跳过远程备份"
    fi
}

# ==================== 主流程 ====================

main() {
    log_message "INFO" "开始执行 MySQL 备份任务"
    
    create_directories
    check_docker_compose
    perform_backup
    cleanup_temp_files
    rotate_backups
    send_notification
    upload_to_remote
    
    log_message "INFO" "MySQL 备份任务完成"
}

# 执行主函数
main "$@"