# backend/Dockerfile
# 第一阶段：使用Maven和JDK17构建JAR包
FROM registry.cn-beijing.aliyuncs.com/liam_test/maven:3.8.5-openjdk-17 AS builder
WORKDIR /app
# 复制所有pom文件和依赖项，利用Docker缓存层加速依赖下载
COPY pom.xml .
COPY yudao-dependencies/pom.xml ./yudao-dependencies/
COPY yudao-framework/pom.xml ./yudao-framework/
COPY yudao-framework/yudao-common/pom.xml ./yudao-framework/yudao-common/
COPY yudao-framework/yudao-spring-boot-starter-biz-data-permission/pom.xml ./yudao-framework/yudao-spring-boot-starter-biz-data-permission/
COPY yudao-framework/yudao-spring-boot-starter-biz-ip/pom.xml ./yudao-framework/yudao-spring-boot-starter-biz-ip/
COPY yudao-framework/yudao-spring-boot-starter-biz-tenant/pom.xml ./yudao-framework/yudao-spring-boot-starter-biz-tenant/
COPY yudao-framework/yudao-spring-boot-starter-excel/pom.xml ./yudao-framework/yudao-spring-boot-starter-excel/
COPY yudao-framework/yudao-spring-boot-starter-job/pom.xml ./yudao-framework/yudao-spring-boot-starter-job/
COPY yudao-framework/yudao-spring-boot-starter-monitor/pom.xml ./yudao-framework/yudao-spring-boot-starter-monitor/
COPY yudao-framework/yudao-spring-boot-starter-mq/pom.xml ./yudao-framework/yudao-spring-boot-starter-mq/
COPY yudao-framework/yudao-spring-boot-starter-mybatis/pom.xml ./yudao-framework/yudao-spring-boot-starter-mybatis/
COPY yudao-framework/yudao-spring-boot-starter-protection/pom.xml ./yudao-framework/yudao-spring-boot-starter-protection/
COPY yudao-framework/yudao-spring-boot-starter-redis/pom.xml ./yudao-framework/yudao-spring-boot-starter-redis/
COPY yudao-framework/yudao-spring-boot-starter-security/pom.xml ./yudao-framework/yudao-spring-boot-starter-security/
COPY yudao-framework/yudao-spring-boot-starter-test/pom.xml ./yudao-framework/yudao-spring-boot-starter-test/
COPY yudao-framework/yudao-spring-boot-starter-web/pom.xml ./yudao-framework/yudao-spring-boot-starter-web/
COPY yudao-framework/yudao-spring-boot-starter-websocket/pom.xml ./yudao-framework/yudao-spring-boot-starter-websocket/
COPY yudao-module-ai/pom.xml ./yudao-module-ai/
COPY yudao-module-bpm/pom.xml ./yudao-module-bpm/
COPY yudao-module-crm/pom.xml ./yudao-module-crm/
COPY yudao-module-erp/pom.xml ./yudao-module-erp/
COPY yudao-module-infra/pom.xml ./yudao-module-infra/
COPY yudao-module-system/pom.xml ./yudao-module-system/
COPY yudao-server/pom.xml ./yudao-server/

# 下载依赖，利用缓存
# 注意：excludeGroupIds 在多模块反应堆(Reactor)模式下可能不生效，
# 我们使用 dependency:resolve 代替 go-offline 来下载插件和依赖，并尝试忽略错误，或者仅下载第三方依赖
# 更好的做法是：先安装父工程和通用模块到本地仓库（但此时没有源码），所以这里我们采用妥协方案：
# 1. 仅下载插件（通常比较慢且通用）
RUN mvn dependency:resolve-plugins -B
# 2. 尝试解析依赖，允许失败（因为内部 SNAPSHOT 肯定找不到），但这样能把大部分第三方 jar 下下来
RUN mvn dependency:resolve -B -DexcludeGroupIds=cn.iocoder.boot || true
# RUN mvn dependency:go-offline -B -DskipTests

# 复制源代码并构建
#（正常推荐两阶段 COPY， 先仅复制 pom 文件，再复制所有文件，但本项目涉及子模块中嵌套子模块的问题，要穷举的话有点麻烦）
#只复制所有 pom 文件：
#构建缓存优化：Docker会为包含pom.xml的层创建缓存，只有当pom文件改变时才重新下载依赖
#构建速度快：只复制少量pom.xml文件，构建上下文小，传输快
#网络效率高：利用Docker层缓存，避免重复下载相同的依赖
#存储效率高：减少了中间镜像层的大小
#复制整个项目文件：
#构建上下文大：包含所有源代码和资源文件，可能导致构建缓慢
#缓存效率低：任何文件变动都会使缓存失效，需要重新下载依赖
#网络开销大：传输大量不必要的文件到Docker守护进程
COPY . .
RUN mvn clean package -DskipTests -Dmaven.test.skip=true

# 第二阶段：创建运行时镜像
#FROM openjdk:17-jdk-slim
FROM registry.cn-beijing.aliyuncs.com/liam_test/openjdk:17-jdk-slim
WORKDIR /app

# 设置时区为中国标准时间
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN echo 'Asia/Shanghai' > /etc/timezone

# 从构建阶段复制JAR包，使用通配符避免硬编码JAR名称
COPY --from=builder /app/yudao-server/target/yudao-server*.jar app.jar
# 暴露端口（与application.yml中配置一致）
EXPOSE 48080
# 启动应用，可通过环境变量覆盖默认配置
ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom -Djava.awt.headless=true -Duser.timezone=GMT+8", "-jar", "/app/app.jar"]