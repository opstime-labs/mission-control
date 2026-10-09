using System.Security.Cryptography;
var builder = WebApplication.CreateBuilder(args);

// 1. Register Health Check Services
builder.Services.AddHealthChecks();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Health probe endpoint for NGINX upstream checks & SIL orchestrator
app.MapGet("/healthz", () => Results.Ok(new { status = "Healthy", timestamp = DateTime.UtcNow }));

// Telemetry endpoint using the static allocation
app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new MissionTelemetry
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            RandomNumberGenerator.GetInt32(-20, 56),
            MissionTelemetryData.Summaries[RandomNumberGenerator.GetInt32(0, MissionTelemetryData.Summaries.Length)]
        ))
        .ToArray();
    return forecast;
});

// 2. Map the /health endpoint for deployment probes & NGINX upstream verification
app.MapHealthChecks("/health");

app.UseAuthorization();
app.MapControllers();

app.Run();

// Static holder avoids repeated heap allocations (resolves CA1861)
internal static class MissionTelemetryData
{
    public static readonly string[] Summaries = ["Nominal", "Elevated", "Degraded", "Critical", "Active"];
}

// Sealed record avoids CA1852 devirtualization warning
internal sealed record MissionTelemetry(DateOnly Date, int TemperatureC, string? Status);