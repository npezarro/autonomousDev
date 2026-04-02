# Autonomous Development Agent

Continuous improvement agent that discovers productive work across all repos and executes it through Claude Code CLI. Runs every 30 minutes via cron.

## Why This Exists

Most AI coding assistants wait for you to tell them what to do. This agent inverts that: it surveys codebases on a schedule, identifies the highest-impact work (build failures, security vulnerabilities, missing tests, code quality issues, dependency updates), and executes it autonomously, creating PRs for human review.

The motivation was simple: across 27+ repositories, there's always low-hanging maintenance work that never gets prioritized. An autonomous agent running on a 30-minute cron can handle the steady stream of small improvements that compound over time.

## How It Works

```
Cron trigger (every 30 min)
  → Survey repos for actionable work (build failures, lint errors, security issues, test gaps)
  → Prioritize by impact (build-breaking > security > quality > maintenance)
  → Execute via Claude Code CLI with agentGuidance behavioral rules
  → Create PR with structured description
  → Report results to Discord for human review
```

## Design Decisions

**Staging-only with human approval gate.** Early runs experimented with autonomous production deploys. After analyzing failure modes (a well-intentioned dependency update that broke a downstream service), the agent was restricted to staging-only. Production deploys require human approval via Discord reaction. This was a deliberate safety decision, not a technical limitation.

**Governed by agentGuidance.** The agent doesn't operate with its own ad-hoc rules. It loads the same behavioral defaults, safety constraints, and coding standards that every manual Claude Code session uses. This means improvements to agentGuidance rules (validated via [claude-bakeoff](https://github.com/npezarro/claude-bakeoff)) automatically improve the autonomous agent's behavior.

**Scoped discovery, not open-ended exploration.** The agent doesn't try to "think of things to do." It has a defined priority list of work categories (build failures first, then security, then tests, then quality). This prevents drift into unnecessary refactoring or speculative improvements.

**Session isolation.** Each run operates in a clean context with its own branch. If a run fails or produces poor output, it doesn't affect other repos or future runs.

## Results

108+ production sessions completed, producing real PRs that were reviewed and merged. The agent handles the kind of work that's individually small but collectively significant: fixing lint errors across repos, updating vulnerable dependencies, adding missing test coverage, standardizing CI workflows.

## Architecture

```
autonomousDev/
├── run.sh           # Entry point, called by cron
├── config.json      # Repo manifest, thresholds, exclusions
├── context/         # Per-repo context and progress logs
└── logs/            # Run history and output
```

## Related Projects

- **[agentGuidance](https://github.com/npezarro/agentGuidance)**: Behavioral governance system that defines the rules this agent follows.
- **[claude-bakeoff](https://github.com/npezarro/claude-bakeoff)**: A/B testing framework used to validate instruction changes before they affect the autonomous agent.

## Requirements

- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Cron (or equivalent scheduler)
- GitHub CLI (`gh`) for PR creation
