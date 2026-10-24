# Stage 1: Build & Publish via .NET 10 SDK
# Run SDK natively on the builder host's platform
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
ARG TARGETARCH
WORKDIR /src

COPY Directory.Build.props nuget.config ./
COPY src/MissionControl.Api/MissionControl.Api.csproj src/MissionControl.Api/
COPY src/MissionControl.Api/packages.lock.json src/MissionControl.Api/

# Restore packages targeting the destination architecture natively
RUN dotnet restore src/MissionControl.Api/MissionControl.Api.csproj \
    --configfile nuget.config \
    --locked-mode \
    -a $TARGETARCH

COPY src/MissionControl.Api/ src/MissionControl.Api/
WORKDIR /src/src/MissionControl.Api

# Cross-compile for the destination architecture natively
RUN dotnet publish MissionControl.Api.csproj \
    -c Release \
    --no-restore \
    -a $TARGETARCH \
    -o /app/publish \
    /p:ContinuousIntegrationBuild=true \
    /p:UseAppHost=false

# Stage 2: Distroless Chiseled Runtime (.NET 10)
# Automatically targets the respective destination platform (amd64 or arm64)
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS final
WORKDIR /app

USER $APP_UID
COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

EXPOSE 8080
ENTRYPOINT ["dotnet", "MissionControl.Api.dll"]