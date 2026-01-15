# backend/Dockerfile
# 第一阶段：使用Maven和JDK17构建JAR包
FROM registry.cn-beijing.aliyuncs.com/liam_test/maven:3.8.5-openjdk-17 AS builder
WORKDIR /app
# 先复制pom文件，利用Docker缓存层加速依赖下载
COPY pom.xml .
RUN mvn dependency:go-offline -B
# 复制源代码并构建
COPY . .
RUN mvn clean package -DskipTests -Dmaven.test.skip=true

# 第二阶段：创建运行时镜像
#FROM openjdk:17-jdk-slim
FROM registry.cn-beijing.aliyuncs.com/liam_test/openjdk:17-jdk-slim
WORKDIR /app
# 从构建阶段复制JAR包，使用通配符避免硬编码JAR名称
COPY --from=builder /app/yudao-server/target/yudao-server*.jar app.jar
# 暴露端口（与application.yml中配置一致）
EXPOSE 48080
# 启动应用，可通过环境变量覆盖默认配置
ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom", "-jar", "/app/app.jar"]