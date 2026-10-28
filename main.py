"""AgentCore direct-code entry point (entryPoint ["main.py"]): the agent is chosen by the ACT_AGENT_NAME environment variable."""

import os

os.environ.setdefault("ACT_HOST", "0.0.0.0")  # AgentCore expects the A2A server on 0.0.0.0:9000
os.environ.setdefault("ACT_PORT", "9000")

from act_teams.server import main

if __name__ == "__main__":
    main()
