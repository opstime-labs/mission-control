#=================================================================================================================
# Build Agent Dockerfile for .NET Development + SonarScanner              
# Build and push this image with the following tagging convention:
# Tag : <dotnet-version>.<java-version>-sonar<scanner-version>-<image-revision>
# For example, for .NET 8.0, Java 21, SonarScanner 9.0.1, and image revision 1:
# docker build -t nexus.homelab.local:8082/infrastructure/dotnet-builder:8.0-java21-9.0.1 docker/build-agent/
# docker push nexus.homelab.local:8082/infrastructure/dotnet-builder:8.0-java21-9.0.1
#==================================================================================================================
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH="/usr/local/bin:${PATH}"

# Install Java 21 LTS headless for SonarQube Scanner CLI
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install dotnet-sonarscanner into the global system binary path
RUN dotnet tool install --tool-path /usr/local/bin dotnet-sonarscanner --version 9.0.1

# Verify permissions
RUN chmod +x /usr/local/bin/dotnet-sonarscanner