# =============================================================================
# Jenkins with Docker CLI, AWS CLI, JCasC - Nameless Company
# =============================================================================
FROM jenkins/jenkins:lts-jdk17

# Switch to root to install packages
USER root

# Install Docker CLI and AWS CLI
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (not the daemon, just the client)
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Add jenkins user to docker group (group ID might vary, will be set at runtime)
RUN groupadd -g 988 docker 2>/dev/null || true \
    && usermod -aG docker jenkins

# Switch back to jenkins user
USER jenkins

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1g"
ENV CASC_JENKINS_CONFIG="/var/jenkins_home/jenkins.yaml"

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# Copy JCasC configuration (will be copied to jenkins_home)
COPY jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml

EXPOSE 8080
