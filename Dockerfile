# ========================================================
# Stage 1: Build & AOT Optimization (Full .NET 8 SDK)
# ========================================================
FROM mcr.microsoft.com/dotnet/sdk:8.0-jammy AS build
WORKDIR /src

# 1. Copy config, root props, and project manifests first for layer caching
COPY Directory.Build.props nuget.config ./
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

# 2. Air-gapped locked restore specifically targeting linux-x64
RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \
    -r linux-x64 \
    --configfile nuget.config \
    --locked-mode

# 3. Copy application source code (excluding bin/obj via .dockerignore)
COPY src/MissionControl.Api/ src/MissionControl.Api/

# 4. Compile and publish with ReadyToRun Ahead-of-Time native binaries
WORKDIR /src/src/MissionControl.Api
RUN dotnet publish MissionControl.Api.csproj \
    --configuration Release \
    -r linux-x64 \
    --no-restore \
    -o /app/publish \
    /p:PublishReadyToRun=true \
    /p:ContinuousIntegrationBuild=true

# ========================================================
# Stage 2: Distroless Non-Root Runtime (Ubuntu Chiseled)
# ========================================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0-jammy-chiseled AS final
WORKDIR /app

# Non-root UID (1654 provided by Chiseled image)
USER $APP_UID

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE 8080

ENTRYPOINT ["dotnet", "MissionControl.Api.dll"]