# backend/Dockerfile
# 第一阶段：使用Maven和JDK17构建JAR包
FROM registry.cn-beijing.aliyuncs.com/liam_test/maven:3.8.5-openjdk-17 AS builder
WORKDIR /app
# # 复制所有pom文件和依赖项，利用Docker缓存层加速依赖下载
#COPY pom.xml .
#COPY yudao-dependencies/pom.xml ./yudao-dependencies/
#COPY yudao-framework/pom.xml ./yudao-framework/
#COPY yudao-server/pom.xml ./yudao-server/
## ... 复制其他需要的模块
RUN mvn dependency:go-offline -B

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
# 从构建阶段复制JAR包，使用通配符避免硬编码JAR名称
COPY --from=builder /app/yudao-server/target/yudao-server*.jar app.jar
# 暴露端口（与application.yml中配置一致）
EXPOSE 48080
# 启动应用，可通过环境变量覆盖默认配置
ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom", "-jar", "/app/app.jar"]