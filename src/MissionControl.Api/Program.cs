var builder = WebApplication.CreateBuilder(args);

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
            Random.Shared.Next(-20, 55),
            MissionTelemetryData.Summaries[Random.Shared.Next(MissionTelemetryData.Summaries.Length)]
        ))
        .ToArray();
    return forecast;
});

app.Run();

// Static holder avoids repeated heap allocations (resolves CA1861)
internal static class MissionTelemetryData
{
    public static readonly string[] Summaries = ["Nominal", "Elevated", "Degraded", "Critical", "Active"];
}

// Sealed record avoids CA1852 devirtualization warning
internal sealed record MissionTelemetry(DateOnly Date, int TemperatureC, string? Status);