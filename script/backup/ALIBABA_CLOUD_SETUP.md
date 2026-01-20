# 阿里云服务器备份配置指南

## 概述

本文档专门针对在阿里云 ECS 实例上运行的 RuoYi-Vue-Pro 项目，提供优化的备份策略和配置建议。

## 阿里云 ECS 优化配置

### 1. 创建备份目录并挂载数据盘（如适用）

如果您有额外的数据盘用于存储备份：

```bash
# 检查是否有额外磁盘
lsblk

# 如果有未使用的磁盘（如 /dev/vdb），进行格式化和挂载
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /opt/yudao/backups
sudo mount /dev/vdb /opt/yudao/backups
sudo chmod 755 /opt/yudao/backups

# 添加到 /etc/fstab 使其永久挂载
echo '/dev/vdb /opt/yudao/backups ext4 defaults 0 0' | sudo tee -a /etc/fstab
```

### 2. 设置备份目录

```bash
sudo mkdir -p /opt/yudao/backups/mysql/{daily,weekly,monthly,temp}
sudo chmod -R 755 /opt/yudao/backups/mysql
```

### 3. 配置阿里云 OSS 存储

#### 安装 ossutil

```bash
# 下载并安装 ossutil
wget http://gosspublic.alicdn.com/ossutil/1.7.15/ossutil64
sudo mv ossutil64 /usr/local/bin/ossutil
sudo chmod 755 /usr/local/bin/ossutil
```

#### 配置 OSS 访问凭证

```bash
# 配置 OSS（需要 AccessKeyId 和 AccessKeySecret）
ossutil config
```

#### 修改备份脚本以支持 OSS 上传

编辑 [mysql_backup.sh](file:///Users/liam/workspace/PersonalTask/study/yudao/Single/ruoyi-vue-pro/script/backup/mysql_backup.sh) 文件，在 [upload_to_remote()](file:///Users/liam/workspace/PersonalTask/study/yudao/Single/ruoyi-vue-pro/yudao-module-infra/src/main/java/cn/iocoder/yudao/module/infra/service/file/FileServiceImpl.java#L173-L187) 函数中添加以下内容：

```bash
upload_to_remote() {
    # 上传到阿里云OSS
    local compressed_file="${BACKUP_DIR}/daily/${DB_NAME}_${DATE}.sql.gz"
    
    if command -v ossutil &> /dev/null; then
        # 设置OSS bucket名称
        local oss_bucket="${OSS_BUCKET_NAME:-your-backup-bucket}"
        local oss_path="mysql-backups/${DB_NAME}/${DATE}/$(basename "$compressed_file")"
        
        if [ -n "$oss_bucket" ] && [ "$oss_bucket" != "your-backup-bucket" ]; then
            log_message "INFO" "上传备份到阿里云OSS: oss://$oss_bucket/$oss_path"
            
            # 上传到OSS
            if ossutil cp "$compressed_file" "oss://$oss_bucket/$oss_path"; then
                log_message "INFO" "成功上传到阿里云OSS"
                
                # 可选：验证上传
                if ossutil stat "oss://$oss_bucket/$oss_path" > /dev/null 2>&1; then
                    log_message "INFO" "OSS 文件验证成功"
                else
                    log_message "WARNING" "OSS 文件验证失败"
                fi
            else
                log_message "ERROR" "上传到阿里云OSS失败"
            fi
        else
            log_message "INFO" "未配置OSS Bucket，跳过远程备份"
        fi
    else
        log_message "INFO" "未安装 ossutil，跳过远程备份"
    fi
}
```

## 阿里云安全组配置

确保您的 ECS 实例安全组允许必要的访问：

- MySQL 端口（3307）仅对本地访问开放
- 应用服务端口（48080）对外网开放
- SSH 端口（22）限制 IP 访问

## 优化备份时间

考虑阿里云的计费周期，建议将备份安排在非高峰时段：

```bash
# 在 setup_cron.sh 中调整备份时间
# 每日凌晨 3:30 执行备份（避开计费整点）
echo "30 3 * * * $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1" >> "$TEMP_CRON"

# 每天上午 6:30 执行监控
echo "30 6 * * * $MONITOR_SCRIPT >> $LOG_DIR/monitor.log 2>&1" >> "$TEMP_CRON"
```

## 阿里云快照集成

除了数据库备份，建议配置系统盘和数据盘的自动快照：

1. 登录阿里云控制台
2. 进入 ECS 管理控制台
3. 选择"快照" -> "自动快照策略"
4. 创建自动快照策略，设置保留时间和执行时间

## 性能优化建议

### 1. 调整备份脚本参数

```bash
# 在备份脚本中增加并发数以提高性能
docker-compose exec mysql \
    mysqldump -u"$DB_USER" -p"$DB_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    --all \
    --ignore-table=mysql.event \
    --hex-blob \
    --skip-lock-tables \
    --compress \  # 启用压缩
    --max_allowed_packet=1G \
    --net_buffer_length=1M \
    --quick \
    --lock-tables=false \
    "$DB_NAME" > "$backup_file"
```

### 2. 设置合理的备份保留策略

根据业务需求和存储成本平衡：

```bash
# 保守策略（小项目）
DAYS_TO_KEEP=3
WEEKS_TO_KEEP=2
MONTHS_TO_KEEP=3

# 标准策略（中型项目）
DAYS_TO_KEEP=7
WEEKS_TO_KEEP=4
MONTHS_TO_KEEP=6

# 严格策略（大型项目或法规要求）
DAYS_TO_KEEP=14
WEEKS_TO_KEEP=8
MONTHS_TO_KEEP=12
```

## 监控和告警

### 1. 配置阿里云云监控

通过阿里云命令行工具(cloudshell)或SDK设置监控：

```bash
# 安装阿里云CLI（如需要）
curl -o aliyun-cli-linux-latest-amd64.tgz https://releases.aliyun.com/tools/cli/linux-amd64/aliyun-cli-linux-latest-amd64.tgz
tar xzvf aliyun-cli-linux-latest-amd64.tgz
sudo mv aliyun /usr/local/bin/
```

### 2. 设置备份状态监控

可以扩展 [backup_monitor.sh](file:///Users/liam/workspace/PersonalTask/study/yudao/Single/ruoyi-vue-pro/script/backup/backup_monitor.sh) 脚本来发送状态到阿里云云监控：

```bash
send_to_cloud_monitor() {
    # 发送备份状态到阿里云自定义监控
    # 这里可以根据阿里云API进行定制开发
    log_message "INFO" "发送监控数据到阿里云"
}
```

## 应急恢复计划

### 1. 紧急恢复脚本

创建一个简化版的紧急恢复脚本：

```bash
#!/bin/bash
# emergency_restore.sh

BACKUP_FILE="$1"
PROJECT_ROOT="/opt/yudao/ruoyi-vue-pro"
DOCKER_COMPOSE_PATH="$PROJECT_ROOT/script/docker/docker-compose.yml"

if [ -z "$BACKUP_FILE" ]; then
    echo "用法: $0 <backup_file>"
    exit 1
fi

echo "停止应用服务..."
docker compose -f "$DOCKER_COMPOSE_PATH" down

echo "执行数据库恢复..."
gunzip -c "$BACKUP_FILE" | docker compose -f "$DOCKER_COMPOSE_PATH" exec -T mysql mysql -uroot -p123456 ruoyi-vue-pro

echo "启动应用服务..."
docker compose -f "$DOCKER_COMPOSE_PATH" up -d

echo "等待服务启动完成..."
sleep 30

echo "检查服务状态..."
docker compose -f "$DOCKER_COMPOSE_PATH" ps
```

### 2. 备份验证脚本

定期验证备份文件的完整性：

```bash
#!/bin/bash
# verify_backup.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    echo "用法: $0 <backup_file>"
    exit 1
fi

echo "验证备份文件: $BACKUP_FILE"

# 检查文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "错误: 备份文件不存在"
    exit 1
fi

# 检查文件大小
FILE_SIZE=$(stat -c%s "$BACKUP_FILE")
if [ "$FILE_SIZE" -lt 1024 ]; then
    echo "警告: 备份文件过小，可能不完整"
fi

# 如果是压缩文件，先解压验证头部
if [[ "$BACKUP_FILE" == *.gz ]]; then
    if ! gunzip -t "$BACKUP_FILE" 2>/dev/null; then
        echo "错误: 压缩文件损坏"
        exit 1
    fi
    echo "压缩文件验证通过"
else
    # 检查 SQL 文件头部
    if head -20 "$BACKUP_FILE" | grep -q "MySQL dump"; then
        echo "SQL 文件头部验证通过"
    else
        echo "警告: 文件可能不是有效的 SQL 备份"
    fi
fi

echo "备份文件验证完成"
```

## 最佳实践总结

1. **分层备份**：本地 + OSS + 快照三重保障
2. **定期验证**：每月至少一次恢复测试
3. **监控告警**：及时发现备份失败等问题
4. **权限管理**：合理设置文件和目录权限
5. **成本控制**：根据业务需求平衡备份频率和存储成本
6. **文档记录**：详细记录恢复步骤和注意事项