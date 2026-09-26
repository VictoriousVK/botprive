"""Shared contracts (docs/CONCEPTION.md Annexes A, B, C and Phase 3).

Two families:
  * engine contracts, produced by deterministic code (ICT objects, risk gate, statistics);
  * agent contracts: the full verdict shown to the member (numbers from tools, ``evidence``),
    and the narrow ``*LLMOut`` models a model is allowed to fill (words, choices, never figures).
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


# ================================================================ Annexe A: ICT engine
class DefinitionRef(BaseModel):
    name: str
    version: str
    params: dict[str, float | int | bool | str] = {}


class Swing(BaseModel):
    kind: Literal["high", "low"]
    price: float
    time_utc: int
    timeframe: str
    definition: DefinitionRef


class FVG(BaseModel):
    kind: Literal["BISI", "SIBI"]
    top: float
    bottom: float
    consequent_encroachment: float
    created_utc: int
    timeframe: str
    status: Literal["open", "partially_mitigated", "mitigated", "inverted"]
    definition: DefinitionRef


class LiquidityPool(BaseModel):
    side: Literal["BSL", "SSL"]
    level: float
    source: str  # PDH, PDL, PWH, PWL, IPDA_HIGH, ASIA_LOW, EQ_HIGH, HTF_SWING_HIGH…
    rank: int
    formed_utc: int
    swept: bool
    swept_utc: Optional[int] = None


class StructureEvent(BaseModel):
    kind: Literal["BOS", "CHoCH", "MSS", "CISD"]
    direction: Literal["bullish", "bearish"]
    level: float
    time_utc: int
    timeframe: str
    displacement: bool


class PDArray(BaseModel):
    kind: Literal["FVG", "IFVG", "OB", "Breaker", "RejectionBlock", "BPR", "OpeningGap"]
    zone_top: float
    zone_bottom: float
    premium_discount: Literal["premium", "discount", "equilibrium"]
    ref_range: tuple[float, float]


class TimeContext(BaseModel):
    utc: int
    ny_time: str  # "2026-10-06 10:12 (NY)"
    killzone: Optional[Literal["Asia", "London", "NY_AM", "NY_Lunch", "NY_PM"]] = None
    macro_window: Optional[str] = None
    silver_bullet_window: Optional[str] = None
    midnight_open: Optional[float] = None
    daily_open_18h: Optional[float] = None
    amd_phase: Literal["accumulation", "manipulation", "distribution", "unknown"] = "unknown"


class SetupCandidate(BaseModel):
    model: Literal["SilverBullet", "MacroBreaker", "DailyOpenSweep", "Venom", "OTE", "Custom"]
    direction: Literal["long", "short"]
    htf_bias: Literal["bullish", "bearish", "neutral"]
    entry_zone: tuple[float, float]
    entry: float
    invalidation: float
    targets: list[float]
    rr: float
    rule_score: int  # computed by rules, never by a model
    min_score: int
    relaxed: bool = False
    rules_passed: list[str]
    rules_failed: list[str]
    evidence_ids: list[str]
    description: str


class ICTAnalysis(BaseModel):
    symbol: str
    tf_entry: str
    tf_htf: str
    as_of: int  # last CLOSED bar used
    price: float
    htf_bias: Literal["bullish", "bearish", "neutral"]
    dealing_range: tuple[float, float]
    premium_discount: Literal["premium", "discount", "equilibrium"]
    time: TimeContext
    swings: list[Swing]
    fvgs: list[FVG]
    pools: list[LiquidityPool]
    structure: list[StructureEvent]
    pd_arrays: list[PDArray]
    setups: list[SetupCandidate]
    rejections: list[str]  # why no setup, per model and direction
    definitions: list[DefinitionRef]
    caveats: list[str] = []


# ================================================================ Annexe B: common agent contract
class Evidence(BaseModel):
    source_id: str
    field: str
    value: str | float
    as_of: int


class AgentVerdict(BaseModel):
    agent: str
    agent_version: str
    label: str
    confidence: int = Field(ge=0, le=100)
    evidence: list[Evidence]
    summary: str
    caveats: list[str] = []
    insufficient_evidence: bool = False
    trace_id: str
    narrated_by: Literal["llm", "rules"] = "rules"

    def last_line(self) -> str:
        return f"VERDICT={self.label};CONFIDENCE={self.confidence};TRACE={self.trace_id}"


# ================================================================ router
Intent = Literal["journal_review", "setup_analysis", "learn", "risk_check", "research", "ea_factory", "account_support", "out_of_scope", "advice_request"]


class RouteDecision(BaseModel):
    intent: Intent
    target: Literal["coach", "analyste", "mentor", "risk_service", "research", "ea_factory", "support", "refuse", "escalate"]
    reason: str
    confidence: int = Field(ge=0, le=100)
    by: Literal["rules", "llm", "menu"] = "rules"


class RouterLLMOut(BaseModel):
    intent: Intent
    confidence: int
    reason: str


# ================================================================ journal / coach
BehaviorKind = Literal["overtrading", "revenge_trade", "size_up_after_loss", "plan_violation", "outside_killzone", "news_window", "stop_widened", "early_exit", "risk_above_plan"]
EmotionDeclared = Literal["calme", "confiant", "neutre", "hesitant", "stresse", "frustre", "euphorique", "fatigue", "impatient"]
MistakeKind = Literal["entree_precoce", "entree_tardive", "sans_setup", "stop_deplace", "sortie_precoce", "taille_excessive", "hors_plan", "revenge", "autre"]


class BehaviorFlag(BaseModel):
    kind: BehaviorKind
    trade_ids: list[str]
    metric: str
    value: float
    threshold: float
    detail: str


class LessonDraft(BaseModel):
    situation: str = Field(max_length=160)
    action: str = Field(max_length=160)
    targets_behavior: BehaviorKind
    source_trade_ids: list[str]


class CoachLLMOut(BaseModel):
    label: Literal["ON_PLAN", "MINOR_DRIFT", "MAJOR_DRIFT", "INSUFFICIENT_DATA"]
    summary: str = Field(max_length=1800)
    priorities: list[BehaviorKind] = Field(max_length=4)
    lessons: list[LessonDraft] = Field(max_length=2)
    reflection_questions: list[str] = Field(max_length=3)
    caveats: list[str] = Field(default_factory=list, max_length=4)


class LessonProposal(BaseModel):
    id: str
    text: str
    situation: str
    action: str
    behavior: BehaviorKind
    source_trade_ids: list[str]


class CoachVerdict(AgentVerdict):
    label: Literal["ON_PLAN", "MINOR_DRIFT", "MAJOR_DRIFT", "INSUFFICIENT_DATA"]
    period: tuple[int, int]
    kpis: dict
    flags: list[BehaviorFlag]
    lessons: list[LessonProposal] = Field(max_length=2)
    reflection_questions: list[str] = Field(max_length=3)


# ================================================================ risk and setups
class RiskGateResult(BaseModel):
    decision: Literal["PASS", "REDUCE", "BLOCK"]
    max_lots: float
    risk_amount: float
    risk_pct: float
    profile: str
    profile_verified: bool
    rules_applied: list[str]
    violations: list[str]
    warnings: list[str]
    disagreement_logged: bool


class SetupStats(BaseModel):
    model: str
    n: int
    win_rate: Optional[float]
    win_rate_ci95: Optional[tuple[float, float]]
    expectancy_r: Optional[float]
    expectancy_r_ci95: Optional[tuple[float, float]]
    sample_warning: bool


class SetupRequest(BaseModel):
    symbol: str = Field(min_length=2, max_length=20)
    tf_entry: Literal["M1", "M5", "M15"] = "M5"
    tf_htf: Literal["H1", "H4", "D1"] = "H1"
    account_id: Optional[str] = None
    source: Literal["user", "tradingview"] = "user"
    alert_id: Optional[str] = None
    note: str = Field(default="", max_length=500)


class AnalysteLLMOut(BaseModel):
    summary: str = Field(max_length=1800)
    plan_alignment: list[str] = Field(max_length=6)
    points_to_check: list[str] = Field(max_length=5)
    caveats: list[str] = Field(default_factory=list, max_length=4)


class SetupAnalysis(AgentVerdict):
    label: Literal["VALID_BY_RULES", "PARTIAL", "INVALID", "NO_SETUP", "INSUFFICIENT_EVIDENCE"]
    symbol: str
    as_of: int
    candidate: Optional[SetupCandidate]
    ict: dict
    risk_gate: Optional[RiskGateResult]
    stats: Optional[SetupStats]
    plan_alignment: list[str]
    points_to_check: list[str]
    expires_at: Optional[int]


# ================================================================ mentor
class Citation(BaseModel):
    doc_id: str
    chunk_id: str
    title: str
    ref: Optional[str] = None
    timestamp_s: Optional[int] = None


class MentorLLMOut(BaseModel):
    label: Literal["ANSWERED", "PARTIAL", "OUT_OF_CORPUS", "REFUSED_ADVICE"]
    answer: str = Field(max_length=2500)
    cited_chunk_ids: list[str] = Field(max_length=6)
    exercise: Optional[str] = Field(default=None, max_length=500)


class MentorAnswer(AgentVerdict):
    label: Literal["ANSWERED", "PARTIAL", "OUT_OF_CORPUS", "REFUSED_ADVICE"]
    citations: list[Citation]
    exercise: Optional[str] = None
    next_module: Optional[str] = None


# ================================================================ research
class ResearchLLMOut(BaseModel):
    summary: str = Field(max_length=2000)
    relevant_news_ids: list[str] = Field(max_length=8)
    caveats: list[str] = Field(default_factory=list, max_length=4)


class Briefing(AgentVerdict):
    label: Literal["RISK_ON", "RISK_OFF", "NEUTRAL", "INSUFFICIENT_EVIDENCE"]
    session: str
    regime_inputs: dict
    high_impact_events: list[dict]
    news: list[dict]
    single_publisher_warning: bool


# ================================================================ Annexe C: memory
class EpisodicMemory(BaseModel):
    period: str
    summary: str
    trajectory: str
    what_worked: str
    what_didnt_work: str
    key_points: list[str]
    strength: float = 1.0
