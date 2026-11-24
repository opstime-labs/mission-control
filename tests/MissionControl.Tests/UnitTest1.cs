namespace MissionControl.Tests;

using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

public class MissionControlApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public MissionControlApiTests(WebApplicationFactory<Program> factory)
    {
         ArgumentNullException.ThrowIfNull(factory);
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetHealthReturnsOkWithStructuredJson()
    {
        // Act
        var response = await _client.GetAsync(new Uri("/health", UriKind.Relative));

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);

        var content = await response.Content.ReadAsStringAsync();
        using var jsonDoc = JsonDocument.Parse(content);
        var root = jsonDoc.RootElement;

        Assert.Equal("Healthy", root.GetProperty("status").GetString());
        Assert.True(root.TryGetProperty("durationMs", out _));
        Assert.True(root.TryGetProperty("entries", out var entries));
        Assert.True(entries.GetArrayLength() > 0);
    }

    [Fact]
    public async Task GetHealthzReturnsOkWithHealthyStatus()
    {
        // Act
        var response = await _client.GetAsync(new Uri("/healthz", UriKind.Relative));

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var content = await response.Content.ReadAsStringAsync();
        using var jsonDoc = JsonDocument.Parse(content);
        Assert.Equal("Healthy", jsonDoc.RootElement.GetProperty("status").GetString());
    }

    [Fact]
    public async Task GetWeatherForecastReturnsFiveTelemetryItems()
    {
        // Act
        var response = await _client.GetAsync(new Uri("/weatherforecast", UriKind.Relative));

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var content = await response.Content.ReadAsStringAsync();
        using var jsonDoc = JsonDocument.Parse(content);
        Assert.Equal(JsonValueKind.Array, jsonDoc.RootElement.ValueKind);
        Assert.Equal(5, jsonDoc.RootElement.GetArrayLength());

        var firstItem = jsonDoc.RootElement[0];
        Assert.True(firstItem.TryGetProperty("temperatureC", out _));
        Assert.True(firstItem.TryGetProperty("status", out var statusProp));
        Assert.False(string.IsNullOrEmpty(statusProp.GetString()));
    }

    [Fact]
    public async Task GetSensorHealthReturnsOkWithTelemetryPayload()
    {
        var response = await _client.GetAsync(new Uri("/api/sensors/health", UriKind.Relative));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = doc.RootElement;

        Assert.Equal("Healthy", root.GetProperty("status").GetString());
        Assert.False(root.GetProperty("hardwarePresent").GetBoolean());
        Assert.Equal("/dev/i2c-1", root.GetProperty("deviceBus").GetString());
        Assert.True(root.GetProperty("sequenceId").GetUInt32() >= 1);
        Assert.Equal(42.5, root.GetProperty("temperatureC").GetDouble(), precision: 1);
        Assert.Equal(3.3, root.GetProperty("busVoltageV").GetDouble(), precision: 1);
    }
}