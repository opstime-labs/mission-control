FROM mcr.microsoft.com/dotnet/sdk:8.0-jammy

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH="/root/.dotnet/tools:${PATH}"

# Install Java 21 LTS headless runtime
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install pinned SonarScanner CLI
RUN dotnet tool install --global dotnet-sonarscanner --version 9.0.1
