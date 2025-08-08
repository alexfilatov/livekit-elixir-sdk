# LiveKit Full Stack Docker Setup

This directory contains a complete Docker Compose setup for running LiveKit with Ingress and Redis services. This setup allows you to test the full LiveKit functionality including Ingress operations locally.

## Services Included

- **LiveKit Server**: Main LiveKit server for room management and WebRTC
- **Ingress Service**: Handles RTMP, WHIP, and URL stream inputs
- **Redis**: Message broker for service communication

## Quick Start

1. **Start the full stack:**

   ```bash
   cd examples/docker
   docker compose up -d
   ```

2. **Verify services are running:**

   ```bash
   docker compose ps
   ```

3. **Test basic functionality:**

   ```bash
   # From the project root
   mix livekit list-rooms --api-key devkey --api-secret secret --url http://localhost:7880
   ```

4. **Test Ingress functionality:**

   ```bash
   # Create RTMP ingress
   mix livekit create-ingress --api-key devkey --api-secret secret --url http://localhost:7880 --input-type RTMP --name test-stream --room test-room --identity streamer

   # List ingress endpoints
   mix livekit list-ingress --api-key devkey --api-secret secret --url http://localhost:7880
   ```

## Service Endpoints

| Service | Endpoint | Purpose |
|---------|----------|---------|
| LiveKit Server | `http://localhost:7880` | HTTP API and WebSocket |
| LiveKit RTC | `localhost:7881` | RTC TCP connections |
| LiveKit RTC UDP | `localhost:7882-7999` | RTC UDP port range |
| Redis | `localhost:6379` | Message broker |
| RTMP Ingress | `rtmp://localhost:1935/live` | RTMP stream input |
| WHIP Ingress | `http://localhost:8080/whip` | WebRTC WHIP input |

## Configuration

### API Credentials

- **API Key**: `devkey`
- **API Secret**: `secret`

⚠️ **Note**: These are development credentials. For production, use secure keys with at least 32 characters.

### Files

- `docker-compose.yml`: Service orchestration
- `livekit.yaml`: LiveKit server configuration
- `ingress.yaml`: Ingress service configuration

## Troubleshooting

### Port Conflicts

If you encounter port conflicts, you can modify the port mappings in `docker-compose.yml`:

```yaml
ports:
  - "7880:7880"   # Change first number to use different host port
```

### Service Health

Check service logs if containers fail to start:

```bash
# Check all services
docker compose logs

# Check specific service
docker compose logs livekit
docker compose logs ingress
docker compose logs redis
```

### Common Issues

1. **Redis port conflict**: Stop existing Redis instances or change port mapping
2. **LiveKit startup failure**: Check configuration syntax in `livekit.yaml`
3. **Ingress connection issues**: Ensure Redis is healthy before Ingress starts

## Stopping Services

```bash
# Stop all services
docker compose down

# Stop and remove volumes
docker compose down -v
```

## Production Considerations

This setup is designed for development and testing. For production:

1. **Security**: Use strong API keys (32+ characters)
2. **Networking**: Configure proper firewall rules and TLS
3. **Resources**: Allocate appropriate CPU/memory based on load
4. **Monitoring**: Add health checks and logging
5. **Persistence**: Configure Redis persistence if needed

## Integration with SDK

This Docker setup works seamlessly with the LiveKit Elixir SDK. All CLI commands and programmatic examples in the main README will work with this local setup.

For more examples, see the Livebooks in `../livebooks/` directory.
