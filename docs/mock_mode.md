# Mock Mode for UI Development

The ExGoCD application supports a mock data mode for UI development without requiring a database connection.

## Enabling Mock Mode

Set the `USE_MOCK_DATA=true` environment variable:

```bash
USE_MOCK_DATA=true mix phx.server
```

Or in `config/dev.exs` for persistent development:

```elixir
config :ex_gocd, :use_mock_data, true
```

## What Gets Mocked

When mock mode is enabled, the following `Agents` context functions return mock data:

- `list_agents/0` - Returns 7 sample agents with various states:
  - Idle enabled agent (production + staging)
  - Building agent (production)
  - Disabled agent (Windows)
  - Elastic Kubernetes agent
  - Lost contact agent
  - Vanilla agent (no resources/environments)
  - Low disk space agent
- `list_active_agents/0` - Returns only enabled, non-deleted agents
- `get_agent_by_uuid/1` - Finds mock agent by UUID
- `enable_agent/1` - Mock enable operation
- `disable_agent/1` - Mock disable operation
- `delete_agent/1` - Mock delete operation
- `register_agent/1` - Creates a mock agent

## Mock Agent Data

Each mock agent includes:

- **Various states**: Idle, Building, LostContact
- **Different OS**: Linux (Ubuntu, Debian, Alpine), Windows, macOS
- **Resources**: docker, linux, chrome, maven, nodejs, kubernetes
- **Environments**: production, staging, testing, development
- **Elastic agents**: Example Kubernetes elastic agent
- **Disk space variations**: From 500 MB to 200 GB

## Use Cases

### UI Development

Work on the agents page without a database:

```bash
USE_MOCK_DATA=true mix phx.server
# Visit http://localhost:4000/agents
```

### Testing UI Edge Cases

The mock data includes edge cases:

- Agent with no resources or environments
- Agent with very low disk space (500 MB)
- Lost contact agent
- Disabled agents
- Elastic agents
- Multiple environments and resources

### Faster Iteration

No database migrations or seed data needed - just start the server and see data.

## Switching Between Modes

**Database Mode (default)**:

```bash
mix phx.server
```

**Mock Mode**:

```bash
USE_MOCK_DATA=true mix phx.server
```

No code changes needed - just toggle the environment variable!

## Implementation

Mock data is defined in `lib/ex_gocd/agents/mock.ex` and automatically used when:

1. `USE_MOCK_DATA=true` environment variable is set
2. Any `ExGoCD.Agents` function is called
3. The function delegates to `ExGoCD.Agents.Mock` instead of database queries

## Adding More Mock Data

Edit `lib/ex_gocd/agents/mock.ex` and add more sample agents to the `list_agents/0` function:

```elixir
def list_agents do
  [
    %Agent{
      uuid: "custom-uuid-here",
      hostname: "custom-agent",
      # ... more fields
    }
    | list_agents()
  ]
end
```
