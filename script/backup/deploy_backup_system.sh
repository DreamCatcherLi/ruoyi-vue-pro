#!/bin/bash

# 一键部署 MySQL 备份系统
# 适用于阿里云服务器上的 RuoYi-Vue-Pro 项目

set -e

# ==================== 配置区域 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
LOG_FILE="/var/log/backup_setup.log"

# ==================== 函数定义 ====================

log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | sudo tee -a "$LOG_FILE"
}

check_prerequisites() {
    log_message "INFO" "检查前置条件"
    
    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        log_message "ERROR" "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker Compose 是否已安装
    if ! command -v docker compose &> /dev/null; then
        log_message "ERROR" "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_message "INFO" "前置条件检查通过"
}

create_backup_structure() {
    log_message "INFO" "创建备份目录结构"
    
    # 使用初始化脚本创建目录结构
    "$SCRIPT_DIR/init_backup_dirs.sh" --create
    
    log_message "INFO" "备份目录结构创建完成"
}

setup_scripts() {
    log_message "INFO" "设置备份脚本权限"
    
    chmod +x "$SCRIPT_DIR/mysql_backup.sh"
    chmod +x "$SCRIPT_DIR/mysql_restore.sh" 
    chmod +x "$SCRIPT_DIR/backup_monitor.sh"
    chmod +x "$SCRIPT_DIR/setup_cron.sh"
    chmod +x "$SCRIPT_DIR/deploy_backup_system.sh"
    
    log_message "INFO" "脚本权限设置完成"
}

configure_oss() {
    log_message "INFO" "配置阿里云OSS备份（可选）"
    
    read -p "是否配置阿里云OSS备份？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "请提供阿里云OSS配置信息："
        read -p "OSS访问密钥ID (AccessKeyId): " ACCESS_KEY_ID
        read -s -p "OSS访问密钥 (AccessKeySecret): " ACCESS_KEY_SECRET
        echo
        read -p "OSS Bucket名称: " BUCKET_NAME
        read -p "OSS Endpoint (默认: oss-cn-hangzhou.aliyuncs.com): " OSS_ENDPOINT
        
        if [ -z "$OSS_ENDPOINT" ]; then
            OSS_ENDPOINT="oss-cn-hangzhou.aliyuncs.com"
        fi
        
        # 安装 ossutil
        if ! command -v ossutil &> /dev/null; then
            log_message "INFO" "安装 ossutil..."
            wget http://gosspublic.alicdn.com/ossutil/1.7.15/ossutil64 -O /tmp/ossutil64
            sudo mv /tmp/ossutil64 /usr/local/bin/ossutil
            sudo chmod 755 /usr/local/bin/ossutil
        fi
        
        # 配置 ossutil
        mkdir -p ~/.ossutil
        cat > ~/.ossutil/config.json << EOF
{
    "Endpoint": "$OSS_ENDPOINT",
    "AccessKeyId": "$ACCESS_KEY_ID",
    "AccessKeySecret": "$ACCESS_KEY_SECRET",
    "STSToken": "",
    "ConfigLanguage": "CN",
    "OutputFormat": "json"
}
EOF
        
        # 更新备份脚本以启用OSS
        sed -i.bak "s/OSS_ENABLED=\${OSS_ENABLED:-false}/OSS_ENABLED=\${OSS_ENABLED:-true}/" "$SCRIPT_DIR/mysql_backup.sh"
        sed -i.bak "s/OSS_BUCKET_NAME=\${OSS_BUCKET_NAME:-\"\"}/OSS_BUCKET_NAME=\${OSS_BUCKET_NAME:-\"$BUCKET_NAME\"}/" "$SCRIPT_DIR/mysql_backup.sh"
        sed -i.bak "s/OSS_ENDPOINT=\${OSS_ENDPOINT:-\"oss-cn-hangzhou.aliyuncs.com\"}/OSS_ENDPOINT=\${OSS_ENDPOINT:-\"$OSS_ENDPOINT\"}/" "$SCRIPT_DIR/mysql_backup.sh"
        
        log_message "INFO" "OSS配置完成"
    else
        log_message "INFO" "跳过OSS配置"
    fi
}

setup_cron_jobs() {
    log_message "INFO" "设置定时备份任务"
    
    # 运行 setup_cron.sh 脚本来设置 cron 任务
    "$SCRIPT_DIR/setup_cron.sh" --setup
    
    log_message "INFO" "定时任务设置完成"
}

test_backup() {
    log_message "INFO" "测试备份功能（这将会创建一个测试备份）"
    
    read -p "是否立即执行一次测试备份？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "INFO" "执行测试备份..."
        "$SCRIPT_DIR/mysql_backup.sh"
        
        if [ $? -eq 0 ]; then
            log_message "INFO" "测试备份成功！"
        else
            log_message "ERROR" "测试备份失败！"
            exit 1
        fi
    else
        log_message "INFO" "跳过测试备份"
    fi
}

show_status() {
    log_message "INFO" "显示备份系统状态"
    
    echo "==================================="
    echo "备份系统部署完成！"
    echo "==================================="
    echo "备份目录: /opt/yudao/backups/mysql"
    echo "备份脚本位置: $SCRIPT_DIR"
    echo "当前 Cron 任务:"
    crontab -l
    echo "==================================="
    echo ""
    echo "使用说明："
    echo "- 手动备份: $SCRIPT_DIR/mysql_backup.sh"
    echo "- 恢复数据: $SCRIPT_DIR/mysql_restore.sh --file <backup_file>"
    echo "- 监控状态: $SCRIPT_DIR/backup_monitor.sh"
    echo "- 查看帮助: $SCRIPT_DIR/mysql_backup.sh --help"
    echo ""
    echo "重要提醒："
    echo "1. 请确保 /opt/yudao/backups/mysql 有足够的磁盘空间"
    echo "2. 定期检查备份日志: /opt/yudao/backups/mysql/backup.log"
    echo "3. 定期测试恢复过程以确保备份有效"
    echo "==================================="
}

show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "一键部署 MySQL 备份系统"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -f, --full     完整部署（包括OSS配置）"
    echo "  -b, --basic    基础部署（无OSS配置）"
    echo ""
    echo "示例:"
    echo "  $0 --full      # 完整部署，包含OSS配置"
    echo "  $0 --basic     # 基础部署，仅本地备份"
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
        -f|--full)
            check_prerequisites
            create_backup_structure
            setup_scripts
            configure_oss
            setup_cron_jobs
            test_backup
            show_status
            exit 0
            ;;
        -b|--basic)
            check_prerequisites
            create_backup_structure
            setup_scripts
            setup_cron_jobs
            test_backup
            show_status
            exit 0
            ;;
        *)
            log_message "ERROR" "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done