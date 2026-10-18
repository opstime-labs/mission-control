using System.Security.Cryptography;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;

var builder = WebApplication.CreateBuilder(args);

// -----------------------------------------------------------------------------
// 1. HOST RUNTIME & KESTREL HARDENING (Ubuntu Chiseled / Non-Root)
// -----------------------------------------------------------------------------
builder.WebHost.ConfigureKestrel(options =>
{
    // Suppress Server header to prevent reconnaissance in multi-tenant SIL enclaves
    options.AddServerHeader = false;
    options.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(15);
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(5);
});

// Enforce graceful shutdown window for NGINX upstream socket draining
builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(10);
});

// -----------------------------------------------------------------------------
// 2. HEALTH & DIAGNOSTIC SERVICES
// -----------------------------------------------------------------------------
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy("Subsystem nominal."), tags: ["live", "ready"]);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Restrict Swagger to Development environments
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// -----------------------------------------------------------------------------
// 3. UNIFIED INGRESS HEALTH PROBES (NGINX & sil-watchdog Target)
// -----------------------------------------------------------------------------
// Maps standard /health endpoint with structured JSON telemetry
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResultStatusCodes =
    {
        [HealthStatus.Healthy] = StatusCodes.Status200OK,
        [HealthStatus.Degraded] = StatusCodes.Status200OK,
        [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
    },
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        var response = new
        {
            status = report.Status.ToString(),
            durationMs = report.TotalDuration.TotalMilliseconds,
            nodeTimestamp = DateTime.UtcNow,
            entries = report.Entries.Select(e => new
            {
                key = e.Key,
                status = e.Value.Status.ToString(),
                description = e.Value.Description
            })
        };
        await context.Response.WriteAsJsonAsync(response);
    }
});

// Legacy /healthz redirected or mapped to unified probe
app.MapGet("/healthz", () => Results.Ok(new { status = "Healthy", timestamp = DateTime.UtcNow }));

// -----------------------------------------------------------------------------
// 4. TELEMETRY APIS
// -----------------------------------------------------------------------------
app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new MissionTelemetry
        (
            DateOnly.FromDateTime(DateTime.UtcNow.AddDays(index)),
            RandomNumberGenerator.GetInt32(-20, 56),
            MissionTelemetryData.Summaries[RandomNumberGenerator.GetInt32(0, MissionTelemetryData.Summaries.Length)]
        ))
        .ToArray();
    return forecast;
});

app.UseAuthorization();
app.MapControllers();

app.Run();

// -----------------------------------------------------------------------------
// 5. CA1861 & CA1852 ROSLYN COMPLIANCE STRUCTURES
// -----------------------------------------------------------------------------
// Static holder eliminates repeated heap allocations (Resolves CA1861)
internal static class MissionTelemetryData
{
    public static readonly string[] Summaries = ["Nominal", "Elevated", "Degraded", "Critical", "Active"];
}

// Sealed record avoids virtual dispatch overhead (Resolves CA1852)
internal sealed record MissionTelemetry(DateOnly Date, int TemperatureC, string? Status);