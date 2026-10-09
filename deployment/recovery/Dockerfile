FROM eclipse-temurin:21-jre-alpine
COPY backend/target/pawday-backend-0.6.3-SNAPSHOT.jar /app.jar
COPY backend/target/test-classes/ /probe/
ENTRYPOINT ["java", "-Dloader.path=/probe", "-Dloader.main=cn.pawday.RecoverySearchProbe", "-cp", "/app.jar", "org.springframework.boot.loader.launch.PropertiesLauncher"]
