pipeline {
    agent any

    environment {
        JENKINS_API = credentials('api')
    }

    stages {
        stage('Docker setup') {
            steps {
                sh "./bin/download_docker.sh"
            }
        }
        stage('Build references') {
            steps {
                sh "rm -rf references/"
                sh "./bin/build_reference.sh"
            }
        }
        stage('Germline') {
            steps {
                sh "rm -rf data/"
                sh "git clone --single-branch --branch sarek https://github.com/nf-core/test-datasets.git data"
                sh "./bin/run_tests.sh --test GERMLINE"
                sh "rm -rf data/"
            }
        }
        stage('Somatic') {
            steps {
                sh "./bin/run_tests.sh --test SOMATIC"
            }
        }
        stage('Targeted') {
            steps {
                sh "./bin/run_tests.sh --test TARGETED"
            }
        }
        stage('Annotation') {
            steps {
                sh "./bin/run_tests.sh --test ANNOTATEALL"
            }
        }
        stage('Multiple') {
            steps {
                sh "./bin/run_tests.sh --test MULTIPLE"
            }
        }
    }

    post {
        failure {
            script {
                def response = sh(script: "curl -u ${JENKINS_API_USR}:${JENKINS_API_PSW} ${BUILD_URL}/consoleText", returnStdout: true).trim().replace('\n', '<br>')
                def comment = pullRequest.comment("## :rotating_light: Buil log output:<br><summary><details>${response}</details></summary>")
            }
        }
    }
}
