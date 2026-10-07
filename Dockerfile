# ========================================================
# Stage 1: Build & AOT Optimization (Full .NET 8 SDK)
# ========================================================
FROM mcr.microsoft.com/dotnet/sdk:8.0-jammy AS build
WORKDIR /src

# Copy ONLY the API project definition, lock file, and root props
COPY Directory.Build.props ./
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

# Restore ONLY the service being containerized
RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \
    -r linux-x64 \
    /p:PublishReadyToRun=true \
    --locked-mode

# Copy ONLY API source code
COPY src/MissionControl.Api/ src/MissionControl.Api/

# Publish ReadyToRun Ahead-of-Time native binaries
WORKDIR /src/src/MissionControl.Api
RUN dotnet publish MissionControl.Api.csproj \
    --configuration Release \
    -r linux-x64 \
    --no-restore \
    -o /app/publish \
    /p:PublishReadyToRun=true

# ========================================================
# Stage 2: Distroless Non-Root Runtime (Ubuntu Chiseled)
# ========================================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0-jammy-chiseled AS final
WORKDIR /app

# Non-root UID (1654 provided by Chiseled)
USER $APP_UID

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE 8080

# Recommended
ENTRYPOINT ["dotnet", "MissionControl.Api.dll"]
# OR 
# ENTRYPOINT ["./MissionControl.Api"]
