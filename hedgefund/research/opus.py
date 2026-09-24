"""Claude Opus 5.5 client for the research layer (Layer 1).

Uses the official Anthropic SDK with structured outputs (``output_config.format``) so every
response is schema-valid JSON, streaming (long, high-effort outputs), and a cached system
prompt. Opus 5.5 always thinks; ``effort`` is the depth/cost control. Nothing returned here
can act on its own: callers store results in the ledger and route proposals to the approval
queue.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from hedgefund.research import schemas
from hedgefund.research.prompts import SYSTEM_PROMPT

DEFAULT_MODEL = "claude-opus-5-5"


class ResearchError(RuntimeError):
    pass


class ResearchRefused(ResearchError):
    pass


@dataclass(frozen=True)
class OpusResult:
    task: str
    data: dict[str, Any]
    model: str
    usage: dict[str, int]
    request_id: str | None


def _evidence_block(evidence: list[dict[str, Any]]) -> str:
    return "<evidence>\n" + json.dumps(evidence, indent=1, sort_keys=True, default=str) + "\n</evidence>"


class OpusResearcher:
    def __init__(self, client: Any = None, model: str = DEFAULT_MODEL, effort: str = "high", max_tokens: int = 64000):
        if client is None:
            import anthropic

            client = anthropic.Anthropic(max_retries=3)
        self.client = client
        self.model = model
        self.effort = effort
        self.max_tokens = max_tokens

    def _call(self, task: str, user_content: str, schema: dict[str, Any]) -> OpusResult:
        with self.client.messages.stream(
            model=self.model,
            max_tokens=self.max_tokens,
            system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": user_content}],
            output_config={"effort": self.effort, "format": {"type": "json_schema", "schema": schema}},
        ) as stream:
            msg = stream.get_final_message()
        if msg.stop_reason == "refusal":
            details = getattr(msg, "stop_details", None)
            raise ResearchRefused(f"{task}: declined ({getattr(details, 'category', None)})")
        if msg.stop_reason == "max_tokens":
            raise ResearchError(f"{task}: output truncated at max_tokens={self.max_tokens}")
        text = "".join(b.text for b in msg.content if getattr(b, "type", None) == "text")
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            raise ResearchError(f"{task}: response was not valid JSON: {e}") from e
        u = msg.usage
        usage = {
            "input_tokens": getattr(u, "input_tokens", 0) or 0,
            "output_tokens": getattr(u, "output_tokens", 0) or 0,
            "cache_read_input_tokens": getattr(u, "cache_read_input_tokens", 0) or 0,
            "cache_creation_input_tokens": getattr(u, "cache_creation_input_tokens", 0) or 0,
        }
        return OpusResult(task, data, getattr(msg, "model", self.model), usage, getattr(msg, "_request_id", None))

    # ---- tasks ----
    def market_scan(self, evidence: list[dict[str, Any]], as_of: str) -> OpusResult:
        prompt = (
            f"Market scan as of {as_of}.\n\n"
            "Analyse BTC/ETH trends, dominance, stablecoin liquidity, funding, open interest, "
            "liquidations, macro conditions, sector rotation, protocol revenue, TVL, token unlocks, "
            "institutional flows, regulatory developments and emerging narratives, using the "
            "evidence below where it applies. Identify 5-10 asymmetric opportunities where "
            "valuation or pricing looks disconnected from fundamentals, adoption or upcoming "
            "catalysts. For each, give catalysts (and whether priced in), competition, the bear "
            "case, invalidation conditions and a testable hypothesis the fund could turn into a "
            "strategy on its configured instruments (or name the data/instruments it would need).\n\n"
            + _evidence_block(evidence)
        )
        return self._call("market_scan", prompt, schemas.MARKET_SCAN)

    def write_memo(self, topic: str, evidence: list[dict[str, Any]]) -> OpusResult:
        prompt = f"Write a research memo on: {topic}\n\n" + _evidence_block(evidence)
        return self._call("research_memo", prompt, schemas.RESEARCH_MEMO)

    def draft_strategy(self, memo: dict[str, Any], instruments: list[str]) -> OpusResult:
        prompt = (
            "Turn the hypothesis in this memo into a machine-readable strategy specification.\n"
            f"Use only these instruments: {', '.join(instruments)}. Parameter values must be your "
            "best prior, not fitted values. Include at least three invalidation rules using metrics "
            "such as rolling_sharpe_90d, strategy_drawdown, avg_slippage_bps, hit_rate, "
            "brier_should_trade. Jev min_confidence must be at least 0.60.\n\n"
            "<evidence>\n" + json.dumps(memo, indent=1, sort_keys=True) + "\n</evidence>"
        )
        return self._call("strategy_draft", prompt, schemas.STRATEGY_DRAFT)

    def review_escalation(self, task: dict[str, Any], evidence: list[dict[str, Any]]) -> OpusResult:
        prompt = (
            "The fast decision model escalated a state it could not judge confidently (confidence "
            "below 0.60) or classified as crisis. Deterministic code has already blocked new risk. "
            "Assess the likely cause and recommend an action; the recommendation goes to the "
            "operator and cannot increase risk.\n\n"
            "<report>\n" + json.dumps(task, indent=1, sort_keys=True, default=str) + "\n</report>\n\n" + _evidence_block(evidence)
        )
        return self._call("escalation_review", prompt, schemas.ESCALATION_REVIEW)

    def overnight_review(self, report_markdown: str, calibration: dict[str, Any]) -> OpusResult:
        prompt = (
            "Overnight review. Analyse today's performance, decisions, failures and calibration. "
            "Propose improvements (new strategies, retirements, parameter or Jev-schema changes, "
            "data sources, investigations). Every proposal will be backtested, replay-tested and "
            "approved by the operator before it changes anything.\n\n"
            "<report>\n" + report_markdown + "\n</report>\n\n"
            "<evidence>\n" + json.dumps({"calibration": calibration}, indent=1, sort_keys=True, default=str) + "\n</evidence>"
        )
        return self._call("overnight_review", prompt, schemas.OVERNIGHT_REVIEW)
