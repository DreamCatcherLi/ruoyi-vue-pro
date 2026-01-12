# 芋道系统 Docker 部署指南

本文档介绍如何使用 Docker Compose 部署芋道系统（前后端分离版本）。

## 环境要求

- Docker 20.10+
- Docker Compose v2+
- Linux 服务器（推荐 Ubuntu 20.04+ 或 CentOS 7+）
- 至少 4GB 内存
- 至少 10GB 磁盘空间

## 环境安装

第一步：安装 Docker
方案 A：如果你使用的是 Alibaba Cloud Linux / CentOS 7/8
### 1. 卸载旧版本（如果有的话）
```bash
sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
```
### 2. 安装依赖包
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

### 3. 配置阿里云的 Docker CE 仓库（国内加速，速度更快）
sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

### 4. 安装 Docker 引擎
sudo yum install -y docker-ce docker-ce-cli containerd.io

### 5. 启动 Docker 并设置开机自启
sudo systemctl start docker
sudo systemctl enable docker

第二步：安装 Docker Compose
方法 1：推荐（通常已随 Docker 一起安装）
在较新的安装包中，Compose 插件通常已经包含在内。你可以直接测试：
#### 注意：这里没有横杠
docker compose version
如果显示了版本号（如 Docker Compose version v2.20.2），就说明已经安装好了，以后使用命令时请用 docker compose（中间无横杠）。

第三步：配置优化（可选但推荐）
## 免 sudo 运行（配置用户组）
默认情况下，运行 docker 命令需要 sudo 权限。为了方便，可以将当前用户加入 docker 组：
### 将当前用户 ($USER) 添加到 docker 组
sudo usermod -aG docker $USER

### 退出终端重新登录，或者运行以下命令刷新组权限
newgrp docker
之后你就可以直接使用 docker ps 而不需要加 sudo 了。

## 配置国内镜像加速器（拉取镜像更快）
编辑配置文件：
```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
"registry-mirrors": ["https://xxxxx.mirror.aliyuncs.com"]
}
EOF
```
注意：你需要登录阿里云容器镜像服务控制台，在“镜像工具” -> “镜像加速器”中获取你专属的 xxxxx.mirror.aliyuncs.com 地址。
配置好后，重启 Docker 生效：
sudo systemctl daemon-reload
sudo systemctl restart docker

## 部署步骤

### 1. 克隆项目

```bash
git clone <项目地址>
cd ruoyi-vue-pro
```

### 2. 编译项目

#### 编译后端

```bash
cd yudao-server
mvn clean package -DskipTests
cd ..
```

#### 编译前端（可选，如果已有构建好的前端文件）

```bash
cd /opt/yudao/yudao-ui-admin-vue3
npm install --registry https://registry.npmmirror.com
npm run build
cd ../../..
```

### 3. 使用部署脚本

项目提供了一键部署脚本，可以简化部署过程：

```bash
# 编译项目并启动服务
./deploy.sh build

# 仅启动服务（如果已经编译好）
./deploy.sh start

# 查看服务状态
./deploy.sh status

# 查看服务日志
./deploy.sh logs

# 停止服务
./deploy.sh stop

# 重启服务
./deploy.sh restart

# 清理所有容器和数据
./deploy.sh cleanup
```

### 4. 手动部署

如果不想使用部署脚本，可以直接使用 Docker Compose：

```bash
# 构建并启动服务
docker-compose up -d --build

# 查看服务状态
docker-compose ps

# 查看服务日志
docker-compose logs -f
```

## 服务配置

### 环境变量

项目使用 `.env` 文件配置环境变量，主要包括：

- `MYSQL_ROOT_PASSWORD`: MySQL root 密码
- `MYSQL_DATABASE`: 数据库名
- `JAVA_OPTS`: Java 虚拟机参数

### 端口映射

- `80`: 前端访问端口
- `48080`: 后端 API 端口
- `3306`: MySQL 端口
- `6379`: Redis 端口

## 服务架构

```
Internet
    |
    v
Nginx (前端 + API 代理)
    |
    v
Backend (Spring Boot)
    |
    v
MySQL + Redis
```

## 配置说明

### 后端配置

后端服务使用 `prod` 配置文件，连接到 Docker 网络中的 MySQL 和 Redis 服务。

### 前端配置

前端使用 Nginx 作为 Web 服务器，API 请求通过 Nginx 反向代理到后端服务。

## 数据持久化

- MySQL 数据持久化到 `mysql_data` 卷
- Redis 数据持久化到 `redis_data` 卷

## 安全建议

1. 修改默认的数据库密码
2. 配置 SSL 证书以启用 HTTPS
3. 限制防火墙访问端口
4. 定期备份数据

## 监控和维护

### 查看服务状态

```bash
docker-compose ps
```

### 查看服务日志

```bash
docker-compose logs -f
```

### 备份数据

```bash
# 备份 MySQL 数据
docker exec yudao-mysql mysqldump -u root -p123456 ruoyi-vue-pro > backup.sql
```

## 常见问题

### 1. 端口冲突

如果端口已被占用，修改 `docker-compose.yml` 中的端口映射。

### 2. 内存不足

修改 `.env` 文件中的 `JAVA_OPTS` 参数，调整 JVM 内存设置。

### 3. 构建失败

确保系统有足够的磁盘空间，并检查网络连接。

### 4. 服务启动失败

检查日志输出，确认依赖服务（MySQL、Redis）已正常启动。

## 性能优化

### JVM 调优

根据服务器配置调整 `JAVA_OPTS`：

```bash
JAVA_OPTS="-Xms1g -Xmx2g -XX:+UseG1GC"
```

### 数据库优化

- 调整 MySQL 配置参数
- 定期优化数据库表
- 启用慢查询日志

### Nginx 优化

- 调整 worker 进程数
- 启用 gzip 压缩
- 配置缓存策略

## 扩展部署

如需扩展部署（如负载均衡、高可用），可以：

1. 使用 Kubernetes 部署
2. 配置负载均衡器
3. 部署多个后端实例
4. 使用外部数据库和缓存服务