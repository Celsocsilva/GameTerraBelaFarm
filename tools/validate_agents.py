"""Validate canonical operational agent contracts and registry."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from orchestration.runtime.task_dispatcher import Dispatcher

REQUIRED = ["Identidade", "missão", "Objetivos", "Competências", "fontes de contexto",
            "Ferramentas", "permissões", "limites", "Contrato de entrada", "Workflow detalhado",
            "Critérios de decisão", "aprovação humana", "Contrato de saída", "colaboração",
            "Falhas", "indicadores", "conclusão"]
registry = Dispatcher(ROOT / "orchestration/config/agents.yaml")
errors = []
expected = {f"AGENT-{i:02d}" for i in range(13)}
if set(registry.agents) != expected:
    errors.append(f"expected AGENT-00..12, got {sorted(registry.agents)}")
for agent, entry in registry.agents.items():
    path = ROOT / entry["file"]
    if not path.is_file():
        errors.append(f"missing {path}")
        continue
    text = path.read_text(encoding="utf-8")
    if agent not in text.splitlines()[0] or "Versão do contrato: 2.0.0" not in text:
        errors.append(f"{path.name}: wrong identity/version")
    for marker in REQUIRED:
        if marker.lower() not in text.lower():
            errors.append(f"{path.name}: missing {marker}")
for name in ("project.godot", "docs/evidence/README.md", "agents/operational-standard.md"):
    if not (ROOT / name).is_file():
        errors.append(f"missing {name}")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"validated {len(registry.agents)} operational agent contracts (12 specialists + orchestrator)")
