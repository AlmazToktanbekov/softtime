#!/bin/zsh

# OmniRoute endpoint
export ANTHROPIC_BASE_URL="http://localhost:20128/v1"

# Любое значение, если OmniRoute без auth
export ANTHROPIC_API_KEY="omniroute"

# Иногда помогает отключить experimental betas
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1

echo "Starting Claude Code via OmniRoute..."
claude
