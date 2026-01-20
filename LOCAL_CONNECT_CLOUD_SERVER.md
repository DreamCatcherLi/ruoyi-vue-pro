# 本地连接云服务器上Docker部署的服务

本文档介绍如何配置本地开发环境以连接到云服务器上Docker部署的MySQL、Redis等服务。

## 配置说明

### 1. 环境变量配置

复制 `.env.local.example` 文件并重命名为 `.env.local`，然后根据你的云服务器实际情况修改配置：

```bash
cp .env.local.example .env.local
```

编辑 `.env.local` 文件，将占位符替换为实际的云服务器信息：

```bash
# 云服务器数据库配置
CLOUD_MYSQL_HOST=your-actual-cloud-server-ip
CLOUD_MYSQL_USERNAME=your-mysql-username
CLOUD_MYSQL_PASSWORD=your-mysql-password

# 云服务器Redis配置
CLOUD_REDIS_HOST=your-actual-cloud-server-ip
CLOUD_REDIS_PASSWORD=your-redis-password

# 云服务器消息队列配置（如有需要）
CLOUD_ROCKETMQ_HOST=your-actual-cloud-server-ip
CLOUD_RABBITMQ_HOST=your-actual-cloud-server-ip
CLOUD_RABBITMQ_USERNAME=your-rabbitmq-username
CLOUD_RABBITMQ_PASSWORD=your-rabbitmq-password
CLOUD_KAFKA_HOST=your-actual-cloud-server-ip
```

### 2. 云服务器Docker配置

根据 [docker-compose.yml](./script/docker/docker-compose.yml) 文件，云服务器上的服务端口映射如下：

- MySQL: 3307 -> 3306
- Redis: 6380 -> 6379
- RabbitMQ: 5672 (如已部署)
- Kafka: 9092 (如已部署)
- RocketMQ: 9876 (如已部署)

### 3. 环境变量加载

为了让Spring Boot应用能够读取环境变量，你需要：

1. 确保环境变量已经导出到系统环境中：
   ```bash
   export $(grep -v '^#' .env.local | xargs)
   ```

2. 或者在IDE中配置运行参数，确保环境变量被正确加载

### 4. 防火墙和安全组配置

确保云服务器的安全组规则已开放以下端口：

- 3307 (MySQL)
- 6380 (Redis)
- 5672 (RabbitMQ，如使用)
- 9092 (Kafka，如使用)
- 9876 (RocketMQ，如使用)

## 注意事项

1. **安全性**: 在生产环境中，确保使用强密码并限制IP访问
2. **网络延迟**: 连接到远程数据库可能会导致较高的网络延迟
3. **SSL连接**: 在生产环境中建议启用SSL连接
4. **连接池**: 可能需要调整连接池参数以适应网络环境

## 故障排除

如果连接失败，请检查：

1. 云服务器防火墙和安全组设置
2. Docker容器的端口映射是否正确
3. 数据库用户是否允许远程连接
4. 网络连通性（可使用 telnet 或 nc 测试）

## 连接测试

可以使用以下命令测试连接：

```bash
# 测试MySQL连接
telnet your-cloud-server-ip 3307

# 测试Redis连接
telnet your-cloud-server-ip 6380
```