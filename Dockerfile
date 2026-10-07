# Stage 1: Build & Publish
FROM mcr.microsoft.com/dotnet/sdk:8.0-jammy AS build
WORKDIR /src

COPY Directory.Build.props nuget.config ./
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \
    --configfile nuget.config \
    --locked-mode

COPY src/MissionControl.Api/ src/MissionControl.Api/

WORKDIR /src/src/MissionControl.Api
RUN dotnet publish MissionControl.Api.csproj \
    -c Release \
    --no-restore \
    -o /app/publish \
    /p:ContinuousIntegrationBuild=true \
    /p:UseAppHost=false

# Stage 2: Distroless Hardened Runtime (Ubuntu Chiseled)
FROM mcr.microsoft.com/dotnet/aspnet:8.0-jammy-chiseled AS final
WORKDIR /app

USER $APP_UID

COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE 8080

ENTRYPOINT ["dotnet", "MissionControl.Api.dll"]