pipeline {
    agent any

    environment {
        JENKINS_API = credentials('api')
    }

    stages {
        stage('Setup environment') {
            steps {
                sh "docker pull nfcore/sarek:dev"
            }
        }
        stage('Build') {
            steps {
              sh "git clone --single-branch --branch sarek https://github.com/nf-core/test-datasets.git test-data"
              sh "nextflow run build.nf -profile docker --genome smallGRCh37 --refdir test-data/reference --outdir References"
            }
        }
        stage('Test') {
            steps {
                sh "nextflow run main.nf -profile docker --help"
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
