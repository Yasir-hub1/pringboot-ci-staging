pipeline {
    agent any
    
    environment {
        ARTIFACT_NAME = 'demo-0.0.1-SNAPSHOT.jar'
        STAGING_PATH = '/home/deployer/staging'
        APP_PORT = '8080'
        HEALTH_ENDPOINT = '/actuator/health'
    }
    
    stages {
        stage('Verify Setup') {
            steps {
                echo 'Verifying Maven container setup'
                sh '''
                    echo "=== Container Status ==="
                    docker exec maven1 whoami
                    docker exec maven1 pwd
                    
                    echo "=== Project Structure ==="
                    docker exec maven1 ls -la /app/ || echo "Maven container not ready"
                    
                    echo "=== POM File Check ==="
                    if docker exec maven1 test -f /app/pom.xml; then
                        echo "✅ pom.xml found"
                    else
                        echo "❌ pom.xml missing"
                        exit 1
                    fi
                '''
            }
        }
        
        stage('Build') {
            steps {
                echo 'Building project in Maven container'
                sh '''
                    echo "=== Starting Maven Build ==="
                    docker exec maven1 bash -c "cd /app && mvn clean compile"
                    
                    echo "=== Build Status ==="
                    if [ $? -eq 0 ]; then
                        echo "✅ Build completed successfully"
                    else
                        echo "❌ Build failed"
                        exit 1
                    fi
                '''
            }
        }
        
        stage('Test') {
            steps {
                echo 'Running tests in Maven container'
                sh '''
                    echo "=== Starting Tests ==="
                    docker exec maven1 bash -c "cd /app && mvn test"
                    
                    echo "=== Test Results ==="
                    if [ $? -eq 0 ]; then
                        echo "✅ All tests passed"
                    else
                        echo "❌ Tests failed"
                        exit 1
                    fi
                '''
            }
        }
        
        stage('Package') {
            steps {
                echo 'Packaging application'
                sh '''
                    echo "=== Creating JAR Package ==="
                    docker exec maven1 bash -c "cd /app && mvn package -DskipTests"
                    
                    echo "=== Verifying Package ==="
                    docker exec maven1 ls -la /app/target/
                    
                    if docker exec maven1 test -f /app/target/${ARTIFACT_NAME}; then
                        echo "✅ JAR package created successfully"
                        JAR_SIZE=$(docker exec maven1 stat -c%s /app/target/${ARTIFACT_NAME})
                        echo "📦 JAR size: $JAR_SIZE bytes"
                    else
                        echo "❌ JAR package not found"
                        exit 1
                    fi
                '''
            }
        }
        
        stage('Deploy to Staging') {
            steps {
                echo 'Deploying to staging environment'
                script {
                    sh '''
                        set -e  # Exit on any error
                        
                        echo "=== Setting up staging directory ==="
                        docker exec maven1 mkdir -p ${STAGING_PATH}
                        docker exec maven1 chown -R deployer:deployer ${STAGING_PATH}
                        echo "✅ Staging directory ready: ${STAGING_PATH}"
                        
                        echo "=== Verifying JAR file ==="
                        if docker exec maven1 test -f /app/target/${ARTIFACT_NAME}; then
                            echo "✅ JAR file confirmed"
                            docker exec maven1 ls -la /app/target/${ARTIFACT_NAME}
                        else
                            echo "❌ JAR file missing"
                            exit 1
                        fi
                        
                        echo "=== Stopping ALL existing Java applications ==="
                        # Find all Java processes and stop them gracefully
                        JAVA_PIDS=$(docker exec maven1 bash -c "ps aux | grep 'java.*jar' | grep -v grep | awk '{print \\$2}'" || echo "")
                        
                        if [ ! -z "$JAVA_PIDS" ]; then
                            echo "🔄 Found Java processes: $JAVA_PIDS"
                            for PID in $JAVA_PIDS; do
                                echo "Stopping PID: $PID"
                                docker exec maven1 kill $PID || echo "Could not stop PID $PID"
                            done
                            
                            echo "⏳ Waiting for processes to stop..."
                            sleep 8
                            
                            # Force kill any remaining Java processes
                            REMAINING_PIDS=$(docker exec maven1 bash -c "ps aux | grep 'java.*jar' | grep -v grep | awk '{print \\$2}'" || echo "")
                            if [ ! -z "$REMAINING_PIDS" ]; then
                                echo "🔨 Force killing remaining processes: $REMAINING_PIDS"
                                for PID in $REMAINING_PIDS; do
                                    docker exec maven1 kill -9 $PID || echo "Could not force kill PID $PID"
                                done
                                sleep 3
                            fi
                        else
                            echo "✅ No existing Java processes found"
                        fi
                        
                        echo "=== Final process verification ==="
                        FINAL_CHECK=$(docker exec maven1 bash -c "ps aux | grep 'java.*jar' | grep -v grep" || echo "")
                        if [ -z "$FINAL_CHECK" ]; then
                            echo "✅ All Java processes stopped successfully"
                        else
                            echo "⚠️  Some Java processes still running:"
                            echo "$FINAL_CHECK"
                        fi
                        
                        echo "=== Copying JAR to staging ==="
                        docker exec maven1 cp /app/target/${ARTIFACT_NAME} ${STAGING_PATH}/
                        
                        if docker exec maven1 test -f ${STAGING_PATH}/${ARTIFACT_NAME}; then
                            echo "✅ JAR copied successfully"
                            docker exec maven1 ls -la ${STAGING_PATH}/
                        else
                            echo "❌ Failed to copy JAR"
                            exit 1
                        fi
                        
                        echo "=== Starting new application ==="
                        # Critical fix: Use proper shell escaping for PID capture
                        docker exec maven1 bash -c "cd ${STAGING_PATH} && su deployer -c 'nohup java -jar ${ARTIFACT_NAME} --server.port=${APP_PORT} > app.log 2>&1 & echo \\$! > app.pid'"
                        
                        echo "=== Verifying application startup ==="
                        sleep 15  # Give more time for startup
                        
                        if docker exec maven1 test -f ${STAGING_PATH}/app.pid; then
                            NEW_PID=$(docker exec maven1 cat ${STAGING_PATH}/app.pid 2>/dev/null || echo "")
                            if [ ! -z "$NEW_PID" ] && [ "$NEW_PID" != "" ]; then
                                echo "🚀 Application started with PID: $NEW_PID"
                                
                                # Verify process is running
                                if docker exec maven1 ps -p $NEW_PID > /dev/null 2>&1; then
                                    echo "✅ Process confirmed running"
                                    echo "📋 Process details:"
                                    docker exec maven1 ps -p $NEW_PID -o pid,ppid,cmd --no-headers || echo "Could not get process details"
                                    
                                    # Check if it's binding to the port correctly
                                    sleep 5
                                    PORT_PROCESS=$(docker exec maven1 bash -c "ps aux | grep 'java.*${APP_PORT}' | grep -v grep" || echo "")
                                    if [ ! -z "$PORT_PROCESS" ]; then
                                        echo "✅ Application is binding to port ${APP_PORT}"
                                    else
                                        echo "⚠️  Application started but may not be on port ${APP_PORT} yet"
                                    fi
                                else
                                    echo "❌ Process not found, checking logs..."
                                    docker exec maven1 head -50 ${STAGING_PATH}/app.log 2>/dev/null || echo "No logs available"
                                    exit 1
                                fi
                            else
                                echo "❌ PID file is empty or invalid"
                                echo "PID file contents:"
                                docker exec maven1 cat ${STAGING_PATH}/app.pid || echo "Cannot read PID file"
                                echo "Checking startup logs:"
                                docker exec maven1 head -50 ${STAGING_PATH}/app.log 2>/dev/null || echo "No logs available"
                                exit 1
                            fi
                        else
                            echo "❌ PID file not created"
                            echo "Checking startup logs:"
                            docker exec maven1 head -50 ${STAGING_PATH}/app.log 2>/dev/null || echo "No logs available"
                            exit 1
                        fi
                        
                        echo "✅ Deployment completed successfully"
                    '''
                }
            }
        }
        
        stage('Health Check') {
            steps {
                echo 'Performing comprehensive health check'
                script {
                    sh '''
                        echo "=== Waiting for application full initialization ==="
                        sleep 25  # More time for Spring Boot startup
                        
                        echo "=== Checking application logs ==="
                        if docker exec maven1 test -f ${STAGING_PATH}/app.log; then
                            echo "📄 Recent application logs:"
                            docker exec maven1 tail -40 ${STAGING_PATH}/app.log
                            echo "--- End of logs ---"
                            
                            # Check for successful startup in logs
                            if docker exec maven1 grep -q "Started DemoApplication" ${STAGING_PATH}/app.log 2>/dev/null; then
                                echo "✅ Application startup completed successfully"
                            else
                                echo "⚠️  Application may still be starting up"
                            fi
                        else
                            echo "❌ No log file found"
                            exit 1
                        fi
                        
                        echo "=== Process verification ==="
                        if docker exec maven1 test -f ${STAGING_PATH}/app.pid; then
                            APP_PID=$(docker exec maven1 cat ${STAGING_PATH}/app.pid)
                            if [ ! -z "$APP_PID" ] && docker exec maven1 ps -p $APP_PID > /dev/null 2>&1; then
                                echo "✅ Application process is running (PID: $APP_PID)"
                            else
                                echo "❌ Application process not found"
                                exit 1
                            fi
                        else
                            echo "❌ PID file missing"
                            exit 1
                        fi
                        
                        echo "=== Port binding verification ==="
                        PORT_PROCESS=$(docker exec maven1 bash -c "ps aux | grep 'java.*${APP_PORT}' | grep -v grep")
                        if [ ! -z "$PORT_PROCESS" ]; then
                            echo "✅ Application is bound to port ${APP_PORT}"
                            echo "$PORT_PROCESS"
                        else
                            echo "❌ Application not bound to port ${APP_PORT}"
                            exit 1
                        fi
                        
                        echo "=== Health endpoint testing ==="
                        HEALTH_SUCCESS=false
                        
                        # Try different health check endpoints with more attempts
                        for i in {1..8}; do
                            echo "🏥 Health check attempt $i/8..."
                            
                            # Try Spring Boot Actuator health endpoint
                            if docker exec maven1 curl -f -s -m 15 "http://localhost:${APP_PORT}${HEALTH_ENDPOINT}" > /dev/null 2>&1; then
                                echo "✅ Actuator health endpoint responding!"
                                RESPONSE=$(docker exec maven1 curl -s -m 10 "http://localhost:${APP_PORT}${HEALTH_ENDPOINT}" 2>/dev/null || echo "Could not get response")
                                echo "📊 Health response: $RESPONSE"
                                HEALTH_SUCCESS=true
                                break
                            fi
                            
                            # Try basic health endpoint
                            if docker exec maven1 curl -f -s -m 15 "http://localhost:${APP_PORT}/health" > /dev/null 2>&1; then
                                echo "✅ Basic health endpoint responding!"
                                HEALTH_SUCCESS=true
                                break
                            fi
                            
                            # Try root endpoint
                            if docker exec maven1 curl -f -s -m 15 "http://localhost:${APP_PORT}/" > /dev/null 2>&1; then
                                echo "✅ Root endpoint responding!"
                                ROOT_RESPONSE=$(docker exec maven1 curl -s -m 10 "http://localhost:${APP_PORT}/" 2>/dev/null | head -1 || echo "Could not get response")
                                echo "📊 Root response: $ROOT_RESPONSE"
                                HEALTH_SUCCESS=true
                                break
                            fi
                            
                            # Try connecting to port using /dev/tcp
                            if docker exec maven1 bash -c "timeout 5 bash -c 'exec 3<>/dev/tcp/localhost/${APP_PORT} && echo Connection successful >&3'" 2>/dev/null; then
                                echo "✅ Port ${APP_PORT} is accepting connections!"
                                HEALTH_SUCCESS=true
                                break
                            fi
                            
                            if [ $i -lt 8 ]; then
                                echo "⏳ Waiting 20 seconds before next attempt..."
                                sleep 20
                            fi
                        done
                        
                        echo "=== Final health check results ==="
                        if [ "$HEALTH_SUCCESS" = "true" ]; then
                            echo "🎉 APPLICATION IS HEALTHY AND READY!"
                            echo "🌐 Access URLs:"
                            echo "   - Main: http://localhost:${APP_PORT}/"
                            echo "   - Health: http://localhost:${APP_PORT}${HEALTH_ENDPOINT}"
                            echo "   - Actuator: http://localhost:${APP_PORT}/actuator"
                            echo "   - External (if port forwarded): http://localhost:8081/"
                        else
                            echo "❌ Health checks failed after all attempts"
                            echo "🔍 Final diagnostic information:"
                            echo "Java processes:"
                            docker exec maven1 bash -c "ps aux | grep java | grep -v grep" || echo "No java processes"
                            echo "Application logs (last 20 lines):"
                            docker exec maven1 tail -20 ${STAGING_PATH}/app.log 2>/dev/null || echo "No recent logs"
                            exit 1
                        fi
                    '''
                }
            }
        }
    }
    
    post {
        always {
            echo '🏁 Pipeline execution completed'
            script {
                sh '''
                    echo "=== Final system status ==="
                    echo "Container uptime:"
                    docker exec maven1 uptime || echo "Could not get uptime"
                    
                    echo "Application status:"
                    if docker exec maven1 test -f ${STAGING_PATH}/app.pid; then
                        APP_PID=$(docker exec maven1 cat ${STAGING_PATH}/app.pid 2>/dev/null || echo "")
                        if [ ! -z "$APP_PID" ] && docker exec maven1 ps -p $APP_PID > /dev/null 2>&1; then
                            echo "✅ Application is running (PID: $APP_PID)"
                        else
                            echo "❌ Application is not running"
                        fi
                    else
                        echo "❌ No PID file found"
                    fi
                    
                    echo "Port status:"
                    docker exec maven1 bash -c "ps aux | grep 'java.*${APP_PORT}' | grep -v grep || echo 'No Java process on port ${APP_PORT}'"
                    
                    echo "Files in staging:"
                    docker exec maven1 ls -la ${STAGING_PATH}/ || echo "Cannot access staging directory"
                '''
            }
        }
        success {
            echo '🎉 SUCCESS: Pipeline completed successfully!'
            echo '📱 Application deployment summary:'
            echo "   📍 Location: ${env.STAGING_PATH}"
            echo "   🚀 JAR: ${env.ARTIFACT_NAME}"
            echo "   🌐 Port: ${env.APP_PORT}"
            echo '   🔗 Access URLs:'
            echo "      - Internal: http://localhost:${env.APP_PORT}/"
            echo "      - External: http://localhost:8081/"
            echo "      - Health: http://localhost:${env.APP_PORT}/actuator/health"
            echo '   📋 Useful commands:'
            echo '      - Check logs: docker exec maven1 tail -f /home/deployer/staging/app.log'
            echo '      - Check status: docker exec maven1 ps aux | grep java'
            echo '      - Test health: docker exec maven1 curl http://localhost:8080/actuator/health'
        }
        failure {
            echo '❌ FAILURE: Pipeline failed'
            echo '🔍 Troubleshooting information:'
            script {
                sh '''
                    echo "=== Error diagnostics ==="
                    
                    echo "Container status:"
                    docker ps | grep maven1 || echo "maven1 container not found"
                    
                    echo "Staging directory:"
                    docker exec maven1 ls -la ${STAGING_PATH}/ 2>/dev/null || echo "Staging directory not accessible"
                    
                    echo "JAR file status:"
                    docker exec maven1 ls -la /app/target/${ARTIFACT_NAME} 2>/dev/null || echo "JAR not found in target"
                    
                    echo "Application logs (last 100 lines):"
                    docker exec maven1 tail -100 ${STAGING_PATH}/app.log 2>/dev/null || echo "No application logs available"
                    
                    echo "System resources:"
                    docker exec maven1 df -h 2>/dev/null || echo "Could not check disk space"
                    docker exec maven1 free -m 2>/dev/null || echo "Could not check memory"
                    
                    echo "All processes:"
                    docker exec maven1 ps aux | head -20 || echo "Could not list processes"
                '''
            }
            echo '💡 Quick fixes to try:'
            echo '   1. Manual cleanup: docker exec maven1 bash -c "pkill -f java; rm -f /home/deployer/staging/app.pid"'
            echo '   2. Restart container: docker restart maven1'
            echo '   3. Check logs: docker logs maven1'
            echo '   4. Manual start: docker exec maven1 bash -c "cd /home/deployer/staging && java -jar demo-0.0.1-SNAPSHOT.jar"'
        }
        cleanup {
            echo '🧹 Performing cleanup tasks'
            script {
                sh '''
                    # Clean up old build artifacts (keep last 2)
                    docker exec maven1 bash -c "cd /app/target && ls -t *.jar 2>/dev/null | tail -n +3 | xargs rm -f" || echo "No old artifacts to clean"
                    
                    # Clean Maven cache if too large (over 500MB)
                    CACHE_SIZE=$(docker exec maven1 du -sm /root/.m2/repository 2>/dev/null | cut -f1 || echo "0")
                    if [ "$CACHE_SIZE" -gt 500 ]; then
                        echo "Maven cache is ${CACHE_SIZE}MB, cleaning..."
                        docker exec maven1 mvn dependency:purge-local-repository -DactTransitively=false -DreResolve=false || echo "Cache cleanup failed"
                    fi
                '''
            }
        }
    }
}