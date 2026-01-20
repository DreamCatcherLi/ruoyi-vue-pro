#!/bin/bash

# 验证备份系统设置
# 检查所有组件是否正确配置

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
DOCKER_COMPOSE_PATH="${PROJECT_ROOT}/script/docker/docker-compose.yml"
BACKUP_DIR="/opt/yudao/backups/mysql"
LOG_FILE="${BACKUP_DIR}/validation.log"

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

validate_prerequisites() {
    log_message "INFO" "验证前置条件"
    
    local failures=0
    
    # 检查 Docker
    if command -v docker &> /dev/null; then
        log_message "INFO" "✓ Docker 已安装: $(docker --version)"
    else
        log_message "ERROR" "✗ Docker 未安装"
        ((failures++))
    fi
    
    # 检查 Docker Compose
    if command -v docker-compose &> /dev/null; then
        log_message "INFO" "✓ Docker Compose 已安装: $(docker-compose --version)"
    else
        log_message "ERROR" "✗ Docker Compose 未安装"
        ((failures++))
    fi
    
    # 检查必要的命令
    for cmd in mysqldump gzip find du; do
        if command -v "$cmd" &> /dev/null; then
            log_message "INFO" "✓ $cmd 已安装"
        else
            log_message "ERROR" "✗ $cmd 未安装"
            ((failures++))
        fi
    done
    
    return $failures
}

validate_project_structure() {
    log_message "INFO" "验证项目结构"
    
    local failures=0
    
    if [ -f "$DOCKER_COMPOSE_PATH" ]; then
        log_message "INFO" "✓ Docker Compose 文件存在: $DOCKER_COMPOSE_PATH"
    else
        log_message "ERROR" "✗ Docker Compose 文件不存在: $DOCKER_COMPOSE_PATH"
        ((failures++))
    fi
    
    if [ -f "$PROJECT_ROOT/script/docker/.env" ]; then
        log_message "INFO" "✓ 环境配置文件存在: $PROJECT_ROOT/script/docker/.env"
    else
        log_message "WARNING" "⚠ 环境配置文件不存在: $PROJECT_ROOT/script/docker/.env"
    fi
    
    return $failures
}

validate_backup_structure() {
    log_message "INFO" "验证备份目录结构"
    
    local failures=0
    
    # 检查备份目录
    for dir in "$BACKUP_DIR" "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly" "$BACKUP_DIR/temp"; do
        if [ -d "$dir" ]; then
            log_message "INFO" "✓ 目录存在: $dir"
        else
            log_message "ERROR" "✗ 目录不存在: $dir"
            ((failures++))
        fi
    done
    
    # 检查权限
    if [ -w "$BACKUP_DIR" ]; then
        log_message "INFO" "✓ 备份目录可写: $BACKUP_DIR"
    else
        log_message "ERROR" "✗ 备份目录不可写: $BACKUP_DIR"
        ((failures++))
    fi
    
    return $failures
}

validate_scripts() {
    log_message "INFO" "验证备份脚本"
    
    local failures=0
    local scripts=(
        "$SCRIPT_DIR/mysql_backup.sh"
        "$SCRIPT_DIR/mysql_restore.sh"
        "$SCRIPT_DIR/backup_monitor.sh"
        "$SCRIPT_DIR/setup_cron.sh"
        "$SCRIPT_DIR/deploy_backup_system.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                log_message "INFO" "✓ 脚本存在且可执行: $script"
            else
                log_message "ERROR" "✗ 脚本存在但不可执行: $script"
                ((failures++))
            fi
        else
            log_message "ERROR" "✗ 脚本不存在: $script"
            ((failures++))
        fi
    done
    
    # 验证脚本语法
    for script in "${scripts[@]}"; do
        if bash -n "$script" 2>/dev/null; then
            log_message "INFO" "✓ 脚本语法正确: $script"
        else
            log_message "ERROR" "✗ 脚本语法错误: $script"
            ((failures++))
        fi
    done
    
    return $failures
}

validate_database_connection() {
    log_message "INFO" "验证数据库连接"
    
    # 加载环境变量
    ENV_FILE_PATH="$PROJECT_ROOT/script/docker/.env"
    if [ -f "$ENV_FILE_PATH" ]; then
        export $(cat "$ENV_FILE_PATH" | grep -v '^#' | xargs)
    fi
    
    local db_name="${MYSQL_DATABASE:-ruoyi-vue-pro}"
    local db_pass="${MYSQL_ROOT_PASSWORD:-123456}"
    
    if docker-compose -f "$DOCKER_COMPOSE_PATH" ps | grep -q "yudao-mysql"; then
        log_message "INFO" "✓ MySQL 容器正在运行"
        
        if docker-compose -f "$DOCKER_COMPOSE_PATH" exec mysql mysqladmin ping -h localhost -u"root" -p"$db_pass" --silent; then
            log_message "INFO" "✓ 可以连接到 MySQL 数据库"
        else
            log_message "ERROR" "✗ 无法连接到 MySQL 数据库"
            return 1
        fi
    else
        log_message "WARNING" "⚠ MySQL 容器未运行，无法验证数据库连接"
        return 0  # 不算作失败，只是无法验证
    fi
}

validate_cron_jobs() {
    log_message "INFO" "验证 Cron 任务"
    
    local cron_count=$(crontab -l 2>/dev/null | grep -c "backup" || echo 0)
    
    if [ "$cron_count" -gt 0 ]; then
        log_message "INFO" "✓ 发现 $cron_count 个备份相关的 Cron 任务"
        crontab -l 2>/dev/null | grep -i backup
    else
        log_message "WARNING" "⚠ 未发现备份相关的 Cron 任务"
    fi
}

validate_oss_config() {
    log_message "INFO" "验证阿里云OSS配置"
    
    if command -v ossutil &> /dev/null; then
        log_message "INFO" "✓ ossutil 已安装"
        
        # 检查配置文件
        if [ -f ~/.ossutil/config.json ]; then
            log_message "INFO" "✓ OSS 配置文件存在"
        else
            log_message "INFO" "ℹ OSS 配置文件不存在 (如果不需要OSS备份则正常)"
        fi
    else
        log_message "INFO" "ℹ ossutil 未安装 (如果不需要OSS备份则正常)"
    fi
}

main() {
    log_message "INFO" "开始验证备份系统设置"
    echo ""
    
    local total_failures=0
    
    validate_prerequisites
    local result=$?
    ((total_failures += result))
    echo ""
    
    validate_project_structure
    local result=$?
    ((total_failures += result))
    echo ""
    
    validate_backup_structure
    local result=$?
    ((total_failures += result))
    echo ""
    
    validate_scripts
    local result=$?
    ((total_failures += result))
    echo ""
    
    validate_database_connection
    local result=$?
    ((total_failures += result))
    echo ""
    
    validate_cron_jobs
    echo ""
    
    validate_oss_config
    echo ""
    
    if [ $total_failures -eq 0 ]; then
        log_message "SUCCESS" "✓ 所有验证通过！备份系统已正确设置。"
        return 0
    else
        log_message "ERROR" "✗ 共有 $total_failures 个验证失败。请修复这些问题后再继续。"
        return 1
    fi
}

main "$@"