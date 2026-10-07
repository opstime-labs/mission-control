# ========================================================
# Stage 1: Build & AOT Optimization (Full .NET 8 SDK)
# ========================================================
FROM mcr.microsoft.com/dotnet/sdk:8.0-jammy AS build
WORKDIR /src

# Copy baseline configuration and project manifests
COPY Directory.Build.props nuget.config ./
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

# Restore dependencies targeting linux-x64 with locked verification
RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \
    -r linux-x64 \
    --configfile nuget.config \
    --locked-mode

# Copy application source code (ignoring bin/obj via .dockerignore and tar exclude)
COPY src/MissionControl.Api/ src/MissionControl.Api/

# Publish using the restored asset cache
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

USER $APP_UID

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE 8080

ENTRYPOINT ["dotnet", "MissionControl.Api.dll"]