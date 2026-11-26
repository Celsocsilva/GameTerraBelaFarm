import tempfile
import unittest
from pathlib import Path
from orchestration.runtime.task_dispatcher import Dispatcher

class DispatcherTests(unittest.TestCase):
    def setUp(self):
        self.config = Path(__file__).parents[1] / "config/agents.yaml"

    def test_all_domains(self):
        dispatcher = Dispatcher(self.config)
        expected = {"coordination":"AGENT-00","product":"AGENT-01","architecture":"AGENT-02","gameplay":"AGENT-03","art":"AGENT-04","ui":"AGENT-05","qa":"AGENT-06","devops":"AGENT-07","review":"AGENT-08","backend":"AGENT-09","database":"AGENT-10","liveops":"AGENT-11","security":"AGENT-12"}
        self.assertEqual(dispatcher.domains, expected)
        self.assertEqual(len(dispatcher.agents), 13)

    def test_new_specialist_handoffs(self):
        dispatcher = Dispatcher(self.config)
        task = {"task_id": "FV-123", "objective": "Backend MVP", "acceptance_criteria": ["verified"]}
        for domain in ("backend", "database", "liveops", "security"):
            with self.subTest(domain=domain):
                target = dispatcher.select(domain)
                self.assertEqual(dispatcher.package(task, target)["target_agent"], target)

    def test_unknown_domain_and_target(self):
        dispatcher = Dispatcher(self.config)
        with self.assertRaises(ValueError):
            dispatcher.select("unknown")
        with self.assertRaises(ValueError):
            dispatcher.package({}, "AGENT-99")

    def test_duplicate_domain(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "agents.yaml"
            config.write_text(self.config.read_text(encoding="utf-8") +
                "  AGENT-99: {file: agents/test.md, level: 2, domains: [database]}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                Dispatcher(config)
