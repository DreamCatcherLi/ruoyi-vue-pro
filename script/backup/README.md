# MySQL 数据库备份方案

## 概述

本方案为 RuoYi-Vue-Pro 项目提供了一套完整的 MySQL 数据库备份解决方案，适用于运行在 Docker Compose 环境下的数据库备份需求。

## 功能特性

- 自动化备份：定时备份数据库
- 增量备份：支持按天、周、月进行备份归档
- 数据压缩：自动压缩备份文件以节省空间
- 生命周期管理：自动清理过期备份
- 监控告警：监控备份状态和磁盘使用情况
- 快速恢复：提供便捷的数据恢复功能
- 阿里云OSS集成：支持备份到云端存储

## 目录结构

```
script/backup/
├── mysql_backup.sh          # 数据库备份脚本
├── mysql_restore.sh         # 数据库恢复脚本
├── backup_monitor.sh        # 备份监控脚本
├── setup_cron.sh           # Cron 任务设置脚本
├── deploy_backup_system.sh # 一键部署脚本
├── .env.example            # 配置示例文件
├── ALIBABA_CLOUD_SETUP.md  # 阿里云配置指南
└── README.md               # 本说明文档
```

## 快速部署

### 方式一：一键部署（推荐）

```bash
# 给予部署脚本执行权限
chmod +x script/backup/deploy_backup_system.sh

# 完整部署（包含阿里云OSS配置）
./script/backup/deploy_backup_system.sh --full

# 或基础部署（仅本地备份）
./script/backup/deploy_backup_system.sh --basic
```

### 方式二：手动部署

#### 1. 设置备份目录

```bash
sudo mkdir -p /opt/yudao/backups/mysql/{daily,weekly,monthly,temp}
sudo chmod -R 755 /opt/yudao/backups/mysql
```

#### 2. 设置脚本权限

```bash
chmod +x script/backup/*.sh
```

#### 3. 配置备份参数

您可以复制配置示例文件并根据实际情况修改：

```bash
cp script/backup/.env.example script/backup/.env
# 编辑 .env 文件以匹配您的环境
```

#### 4. 设置自动备份

```bash
# 验证脚本语法
./script/backup/setup_cron.sh --validate

# 完整设置备份环境
./script/backup/setup_cron.sh --setup
```

## 阿里云OSS集成

如果需要将备份同步到阿里云OSS：

1. 安装 ossutil：
```bash
wget http://gosspublic.alicdn.com/ossutil/1.7.15/ossutil64
sudo mv ossutil64 /usr/local/bin/ossutil
sudo chmod 755 /usr/local/bin/ossutil
```

2. 配置OSS访问凭证：
```bash
ossutil config
```

3. 在备份脚本中启用OSS功能：
```bash
# 编辑 mysql_backup.sh 文件，将 OSS_ENABLED 设置为 true
OSS_ENABLED=true
OSS_BUCKET_NAME=your-bucket-name
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com
```

## 使用方法

### 手动备份

```bash
./script/backup/mysql_backup.sh
```

### 恢复数据库

```bash
# 列出可用的备份
./script/backup/mysql_restore.sh --list

# 从指定备份文件恢复
./script/backup/mysql_restore.sh --file /opt/backups/mysql/daily/ruoyi-vue-pro_20231201_120000.sql.gz
```

### 监控备份状态

```bash
./script/backup/backup_monitor.sh
```

### 管理 Cron 任务

```bash
# 查看当前任务
./script/backup/setup_cron.sh --list

# 移除任务
./script/backup/setup_cron.sh --remove
```

## 备份策略

### 日常备份
- 每天凌晨 2 点执行
- 保留最近 7 天的备份

### 周备份
- 每周日执行（从最新的日常备份创建）
- 保留最近 4 周的备份

### 月备份
- 每月第一天执行（从最新的日常备份创建）
- 保留最近 6 个月的备份

## 高级配置

### 自定义备份时间

编辑 `setup_cron.sh` 文件，修改 Cron 表达式：

```bash
# 每日凌晨 2 点执行备份
echo "0 2 * * * $BACKUP_SCRIPT >> $LOG_DIR/backup.log 2>&1" >> "$TEMP_CRON"

# 每天早上 6 点执行监控
echo "0 6 * * * $MONITOR_SCRIPT >> $LOG_DIR/monitor.log 2>&1" >> "$TEMP_CRON"
```

### 调整保留策略

编辑 [mysql_backup.sh](file:///Users/liam/workspace/PersonalTask/study/yudao/Single/ruoyi-vue-pro/script/backup/mysql_backup.sh) 文件，修改保留天数：

```bash
DAYS_TO_KEEP=14      # 保留 14 天的日常备份
WEEKS_TO_KEEP=8      # 保留 8 周的周备份
MONTHS_TO_KEEP=12    # 保留 12 个月的月备份
```

## 故障排除

### 权限问题
如果遇到权限问题，请确认：
- 脚本具有执行权限：`chmod +x script/backup/*.sh`
- 备份目录权限正确：`sudo chmod 755 /opt/backups/mysql`

### Docker 连接问题
如果备份脚本无法连接到 MySQL 容器：
- 确认 Docker Compose 服务正在运行
- 检查数据库连接参数是否正确

### 磁盘空间不足
- 定期清理过期备份
- 调整备份保留策略
- 考虑将备份文件同步到云端存储

## 安全建议

- 定期测试备份文件的完整性
- 将备份文件存储在不同的物理位置
- 对备份文件进行加密（如有敏感数据）
- 定期演练恢复过程
- 监控备份作业的执行状态

## 维护计划

- 每周检查备份日志: /opt/yudao/backups/mysql/backup.log
- 每月测试备份恢复过程
- 根据业务增长调整备份保留策略
- 定期评估备份存储成本