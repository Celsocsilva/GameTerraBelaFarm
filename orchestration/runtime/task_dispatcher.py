"""Dispatcher for the repository's constrained inline agent registry format."""
from pathlib import Path
import re

ENTRY = re.compile(r"^  (AGENT-\d{2}): \{file: (agents/[a-z0-9-]+\.md), level: ([0-5]), domains: \[([a-z0-9_, -]+)\]\}$")

class Dispatcher:
    def __init__(self, config: Path):
        self.config = config
        self.agents = {}
        self.domains = {}
        for line in config.read_text(encoding="utf-8").splitlines():
            if not line.startswith("  AGENT-"):
                continue
            match = ENTRY.fullmatch(line)
            if not match:
                raise ValueError(f"invalid agent registry entry: {line}")
            agent, file, level, raw_domains = match.groups()
            if agent in self.agents:
                raise ValueError(f"duplicate agent: {agent}")
            domains = [item.strip() for item in raw_domains.split(",")]
            self.agents[agent] = {"file": file, "level": int(level), "domains": domains}
            for domain in domains:
                if not domain or domain in self.domains:
                    raise ValueError(f"invalid or duplicate domain: {domain}")
                self.domains[domain] = agent
        if "AGENT-00" not in self.agents:
            raise ValueError("missing orchestrator")

    def select(self, domain: str) -> str:
        if domain not in self.domains:
            raise ValueError(f"unknown domain: {domain}")
        return self.domains[domain]

    def package(self, task: dict, target_agent: str) -> dict:
        if target_agent not in self.agents:
            raise ValueError(f"unknown agent: {target_agent}")
        return {"schema_version": 1, "execution_id": task.get("execution_id", task["task_id"] + "-run-1"),
                "task_id": task["task_id"], "source_agent": "AGENT-00", "target_agent": target_agent,
                "objective": task["objective"], "inputs": task.get("inputs", []),
                "expected_outputs": task.get("expected_outputs", []),
                "acceptance_criteria": task["acceptance_criteria"], "dependencies": task.get("dependencies", []),
                "evidence": [], "status": "READY"}
