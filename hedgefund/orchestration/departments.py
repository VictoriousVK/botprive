"""The fund's internal departments as data: responsibilities, workflows, inputs, outputs and
review process, and which layer does the work. This registry is the contract the
orchestration layer (AgentKit or the local runner) implements; `python -m hedgefund org`
prints it."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Department:
    name: str
    mandate: str
    layer: str  # opus | orchestration | jev | deterministic | human
    responsibilities: tuple[str, ...]
    workflows: tuple[str, ...]
    inputs: tuple[str, ...]
    outputs: tuple[str, ...]
    review: str
    code: tuple[str, ...]


DEPARTMENTS: tuple[Department, ...] = (
    Department(
        "CIO",
        "Own the investment agenda and capital allocation across strategies; arbitrate between desks.",
        "opus + human",
        ("set research priorities", "propose capital allocation changes", "chair the Investment Committee", "weekly strategy portfolio review"),
        ("overnight_research", "weekly_allocation_review"),
        ("daily reports", "strategy metrics", "risk utilisation", "calibration reports"),
        ("allocation proposals (approval queue)", "research priorities"),
        "every allocation change requires operator approval",
        ("hedgefund/research/opus.py", "hedgefund/research/pipeline.py"),
    ),
    Department(
        "Research Desk",
        "Find and document asymmetric opportunities; turn observations into falsifiable hypotheses.",
        "opus",
        ("daily market scan (5-10 opportunities)", "research memos with dated sources", "escalation reviews", "failure analysis"),
        ("overnight_research", "escalation_review"),
        ("market evidence from the data pipeline", "escalation queue", "operator questions"),
        ("research memos (ledger)", "hypotheses", "strategy drafts at stage=hypothesis"),
        "memos separate facts (sourced, dated) from interpretation; Investment Committee reads before any spec advances",
        ("hedgefund/research/",),
    ),
    Department(
        "Quant Desk",
        "Convert hypotheses into specs and code; backtest, cost-model and stress-test them honestly.",
        "orchestration + deterministic",
        ("StrategySpec authoring", "signal implementation", "backtests with costs", "stress and parameter-robustness tests", "deflated-Sharpe accounting of trials"),
        ("strategy_pipeline", "recalibration"),
        ("hypotheses", "point-in-time data"),
        ("specs", "strategy code", "evidence bundles for gates"),
        "lifecycle gates (hedgefund/strategy/lifecycle.py); synthetic evidence never passes",
        ("hedgefund/strategy/", "hedgefund/backtest/"),
    ),
    Department(
        "Fundamental Desk",
        "Protocol revenue, token supply/unlocks, competitive position and valuation for sector ideas.",
        "opus",
        ("protocol and token fundamentals", "unlock and supply calendars", "valuation vs adoption"),
        ("overnight_research",),
        ("fundamental data sources (to be added per strategy)",),
        ("memos", "catalyst calendars"),
        "facts must cite a dated source; unverified figures are labelled",
        ("hedgefund/research/",),
    ),
    Department(
        "Macro Desk",
        "Dollar liquidity, rates, risk appetite, regulation and their transmission into crypto.",
        "opus",
        ("macro regime view", "stablecoin liquidity monitoring", "regulatory developments"),
        ("overnight_research",),
        ("stablecoin supply", "market evidence"),
        ("regime memos", "macro strategy specs (e.g. S4)"),
        "Investment Committee",
        ("hedgefund/research/", "hedgefund/strategy/library/stablecoin.py"),
    ),
    Department(
        "On-Chain Desk",
        "Funding, open interest, liquidations, flows, TVL and on-chain supply signals.",
        "opus + deterministic",
        ("derivatives positioning", "liquidation monitoring", "on-chain flow signals"),
        ("overnight_research", "fast_loop"),
        ("funding, OI, stablecoin data",),
        ("features", "memos", "strategy specs (S1, S3)"),
        "Investment Committee",
        ("hedgefund/data/features.py", "hedgefund/data/sources.py"),
    ),
    Department(
        "Portfolio Manager",
        "Run the live books: signals -> Jev -> policy targets; attribution and rebalancing discipline.",
        "jev + deterministic",
        ("per-bar decision loop", "position targets", "PnL attribution per strategy"),
        ("fast_loop", "evening_review"),
        ("market data", "strategy signals", "Jev decisions"),
        ("policy results", "books"),
        "every decision is in the ledger with its Jev state, decision id and reasons",
        ("hedgefund/pipeline.py", "hedgefund/policy/engine.py", "hedgefund/portfolio/book.py"),
    ),
    Department(
        "Risk Committee",
        "Own hard limits, the kill switch and invalidation rules. Can always reduce risk; never increases it.",
        "deterministic + human",
        ("limit enforcement", "drawdown / daily-loss controls", "kill switch", "invalidation monitoring", "limit changes (human)"),
        ("fast_loop", "overnight_invalidation"),
        ("orders", "NAV", "positions", "strategy metrics"),
        ("risk verdicts", "halts / demotions", "kill switch events"),
        "limit changes and kill-switch resets require a named operator; models have no write path",
        ("hedgefund/risk/", "config/risk_limits.yaml", "hedgefund/strategy/monitor.py"),
    ),
    Department(
        "Execution Desk",
        "Get fills safely: idempotent orders, retries, rate limits, reconciliation, execution-quality logging.",
        "deterministic",
        ("order routing", "partial fills and cancel/replace", "reconciliation", "slippage measurement"),
        ("fast_loop",),
        ("risk-approved order requests",),
        ("orders", "fills", "reconciliation reports"),
        "slippage vs model reviewed nightly; mismatch triggers kill switch",
        ("hedgefund/execution/",),
    ),
    Department(
        "Engineering Desk",
        "Build, test and deploy the system; own data pipelines, adapters and monitoring.",
        "orchestration (AgentKit) + human",
        ("CI tests", "venue/data adapters", "deployments", "monitoring and alerting", "incident response"),
        ("deploy", "health_check"),
        ("specs", "incidents", "approval decisions"),
        ("code", "tests", "releases"),
        "no deploy without green tests; live adapters verified on testnet first",
        ("tests/", "hedgefund/ops/", "hedgefund/monitoring/"),
    ),
    Department(
        "Investment Committee",
        "Promotion decisions: evidence review at each lifecycle gate; operator signs LIVE.",
        "deterministic gates + opus review + human",
        ("gate evaluation", "red-team review of specs", "approval of paper -> shadow -> live"),
        ("strategy_pipeline",),
        ("evidence bundles", "memos", "risk review"),
        ("stage transitions (ledger)", "approval decisions"),
        "gates are code; LIVE requires a named human approval",
        ("hedgefund/strategy/lifecycle.py",),
    ),
)
