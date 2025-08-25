pipeline {
    agent any
    
    environment {
        STAGING_SERVER = 'deployer@maven1'
        ARTIFACT_NAME = 'demo-0.0.1-SNAPSHOT.jar'
        STAGING_PATH = '/home/deployer/staging'
    }
    
    stages {
        stage('Prepare Workspace') {
            steps {
                echo 'Ensuring project files are available'
                
                script {
                    sh '''
                        echo "=== Jenkins Workspace Content ==="
                        ls -la
                        pwd
                        
                        echo "=== Restructuring files if needed ==="
                        if [ -d app ] && [ -f app/pom.xml ]; then
                            echo "Moving files from app/ to root level"
                            cp -r app/* .
                            rm -rf app
                            ls -la
                        fi
                        
                        echo "=== Copying to Maven using tar pipe ==="
                        tar cf - . | docker exec -i maven1 bash -c "cd /app && tar xf -"
                        
                        echo "=== Verifying Maven container ==="
                        docker exec maven1 ls -la /app/
                        
                        echo "=== Checking critical files ==="
                        if docker exec maven1 test -f /app/pom.xml; then
                            echo "SUCCESS: pom.xml found"
                        else
                            echo "WARNING: pom.xml not found"
                        fi
                        
                        docker exec maven1 find /app -name "*.java" || echo "No Java files found"
                    '''
                }
            }
        }
        
        stage('Build') {
            steps {
                script {
                    sh '''
                        echo "Building project in Maven container..."
                        docker exec maven1 bash -c "cd /app && mvn clean compile"
                    '''
                }
            }
        }
        
        stage('Test') {
            steps {
                script {
                    sh '''
                        echo "Running tests in Maven container..."
                        docker exec maven1 bash -c "cd /app && mvn test"
                    '''
                }
            }
        }
        
        stage('Code Coverage') {
            steps {
                script {
                    sh '''
                        echo "Generating code coverage report..."
                        docker exec maven1 bash -c "cd /app && mvn jacoco:report"
                        
                        # Crear directorio para reportes
                        mkdir -p target/site/jacoco
                        
                        # Copiar reportes de vuelta a Jenkins
                        docker cp maven1:/app/target/site/jacoco/. ./target/site/jacoco/ || echo "Coverage report copy failed"
                    '''
                }
                publishHTML([
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'target/site/jacoco',
                    reportFiles: 'index.html',
                    reportName: 'JaCoCo Coverage Report'
                ])
            }
        }
        
        stage('Code Quality - Checkstyle') {
            steps {
                script {
                    try {
                        sh '''
                            echo "Running Checkstyle analysis..."
                            docker exec maven1 bash -c "cd /app && mvn checkstyle:check"
                        '''
                    } catch (Exception e) {
                        echo "Checkstyle warnings found, continuing..."
                        sh '''
                            docker exec maven1 bash -c "cd /app && mvn checkstyle:checkstyle"
                        '''
                    }
                    
                    // Crear directorio y copiar reportes de checkstyle
                    sh '''
                        mkdir -p target/site
                        docker cp maven1:/app/target/site/checkstyle.html ./target/site/ || echo "No checkstyle report found"
                    '''
                }
                publishHTML([
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'target/site',
                    reportFiles: 'checkstyle.html',
                    reportName: 'Checkstyle Report'
                ])
            }
        }
        
        stage('Package') {
            steps {
                script {
                    sh '''
                        echo "Packaging application..."
                        docker exec maven1 bash -c "cd /app && mvn package -DskipTests"
                        
                        # Crear directorio target y copiar el JAR
                        mkdir -p target
                        docker cp maven1:/app/target/${ARTIFACT_NAME} ./target/ || echo "JAR copy failed"
                        
                        # Verificar que el JAR se creó
                        ls -la target/
                    '''
                }
            }
        }
        
        stage('Deploy to Staging') {
            steps {
                script {
                    sh '''
                        echo "Deploying to staging environment..."
                        
                        # Detener cualquier instancia anterior directamente en el contenedor
                        docker exec maven1 bash -c "pkill -f 'java -jar' || echo 'No previous instances found'"
                        
                        # Copiar el artefacto ya está en el contenedor Maven
                        docker exec maven1 bash -c "cp /app/target/${ARTIFACT_NAME} ${STAGING_PATH}/ || echo 'JAR already in staging'"
                        
                        # Iniciar la aplicación directamente en el contenedor Maven
                        docker exec maven1 bash -c "cd ${STAGING_PATH} && nohup java -jar ${ARTIFACT_NAME} > app.log 2>&1 & echo \\$! > app.pid"
                        
                        echo "Application deployed successfully"
                    '''
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    sh '''
                        echo "Waiting for application to start..."
                        sleep 30
                    '''
                    
                    retry(5) {
                        sh '''
                            echo "Performing health check..."
                            docker exec maven1 curl -f http://localhost:8080/health || docker exec maven1 curl -f http://localhost:8080/ || exit 1
                        '''
                    }
                    
                    echo "Health check passed - Application is running!"
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
            deleteDir()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}