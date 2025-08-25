pipeline {
    agent any
    
    environment {
        STAGING_SERVER = 'deployer@maven1'
        ARTIFACT_NAME = 'demo-0.0.1-SNAPSHOT.jar'
        STAGING_PATH = '/home/deployer/staging'
    }
    
    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main', url: 'https://github.com/your-org/your-springboot-repo.git'
            }
        }
        
        stage('Build') {
            steps {
                sh 'mvn clean compile'
            }
        }
        
        stage('Test') {
            steps {
                sh 'mvn test'
                publishTestResults testResultsPattern: 'target/surefire-reports/*.xml'
            }
        }
        
        stage('Code Coverage') {
            steps {
                sh 'mvn jacoco:report'
                publishHTML([
                    allowMissing: false,
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
                        sh 'mvn checkstyle:check'
                    } catch (Exception e) {
                        echo "Checkstyle warnings found, continuing..."
                        sh 'mvn checkstyle:checkstyle'
                    }
                }
                publishHTML([
                    allowMissing: false,
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
                sh 'mvn package -DskipTests'
            }
        }
        
        stage('Deploy to Staging') {
            steps {
                script {
                    // Detener cualquier instancia anterior
                    sh '''
                        ssh -o StrictHostKeyChecking=no ${STAGING_SERVER} "pkill -f 'java -jar' || true"
                    '''
                    
                    // Copiar el artefacto
                    sh '''
                        scp -o StrictHostKeyChecking=no target/${ARTIFACT_NAME} ${STAGING_SERVER}:${STAGING_PATH}/
                    '''
                    
                    // Iniciar la aplicación
                    sh '''
                        ssh -o StrictHostKeyChecking=no ${STAGING_SERVER} "cd ${STAGING_PATH} && nohup java -jar ${ARTIFACT_NAME} > app.log 2>&1 & echo $! > app.pid"
                    '''
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    sh 'sleep 30' // Esperar que la aplicación inicie
                    
                    retry(5) {
                        sh '''
                            ssh -o StrictHostKeyChecking=no ${STAGING_SERVER} "curl -f http://localhost:8080/actuator/health || curl -f http://localhost:8080/health || curl -f http://localhost:8080/"
                        '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}