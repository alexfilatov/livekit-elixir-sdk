# LiveKit Voice Agent Livebooks

This directory contains interactive Livebook notebooks for working with LiveKit Voice Agents.

## Setup Instructions

### 1. Prerequisites

Make sure you have the following installed:
- Elixir 1.15+
- Livebook (`mix escript.install hex livebook`)
- API keys for:
  - LiveKit (server URL, API key, API secret)
  - Deepgram (for speech-to-text)
  - OpenAI (for LLM and text-to-speech)

### 2. Compile the LiveKit Project

Before running any Livebooks, compile the LiveKit project:

```bash
cd /path/to/livekit
mix deps.get
mix compile
```

### 3. Start Livebook

From the LiveKit project root directory:

```bash
livebook server
```

### 4. Open the Voice Agent Demo

Navigate to the Livebook web interface and open:
- `examples/livebooks/voice_agent_interactive.livemd`

## Available Livebooks

### 🎤 voice_agent_interactive.livemd

A complete interactive demo that allows you to:
- Configure voice agents with your API keys
- Connect to LiveKit rooms
- Have real-time voice conversations with AI agents
- Monitor agent performance and metrics
- Test different voice models and configurations

**Features:**
- Easy configuration with web forms
- Real-time status monitoring
- Interactive controls for testing
- Browser integration for voice chat
- Comprehensive metrics dashboard

## API Keys Required

To use the voice agent features, you'll need:

1. **LiveKit Server**
   - Server URL (e.g., `ws://localhost:7880` or your LiveKit Cloud URL)
   - API Key
   - API Secret

2. **Deepgram** (for STT)
   - API Key from [Deepgram Console](https://console.deepgram.com/)

3. **OpenAI** (for LLM and TTS)
   - API Key from [OpenAI Platform](https://platform.openai.com/api-keys)

## Troubleshooting

### "Could not compile :livekit" Error

This usually means the LiveKit project isn't compiled. Run:
```bash
mix deps.get
mix compile
```

### Modules Not Loading

Make sure you're running Livebook from the LiveKit project root directory, not from within the `examples/livebooks` folder.

### Connection Issues

- Verify your LiveKit server is running
- Check that your API credentials are correct
- Ensure your firewall allows WebRTC connections

### Audio Issues

- Use Chrome or Firefox for best WebRTC support
- Enable microphone and speaker permissions
- Use headphones to prevent audio feedback

## Development

To modify or extend the Livebooks:

1. Edit the `.livemd` files directly
2. The Livebooks automatically reload when saved
3. Check the console output for any compilation errors
4. Test with different API configurations

## Examples

The voice agent demo includes examples of:
- Basic voice conversations
- Multi-participant rooms
- Real-time metrics monitoring
- Different AI model configurations
- Audio processing demonstrations

For more advanced examples, see the `test/` directory for additional voice agent test cases.