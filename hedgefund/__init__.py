"""One-person, 24/7 AI hedge fund.

Three layers, strictly separated:

* Layer 1 - Claude Opus 5.5 (``hedgefund.research``): slow, deep research, strategy
  design and overnight review. Advisory only; it never touches orders.
* Layer 2 - Orchestration (``hedgefund.orchestration`` / ``hedgefund.ops``): departments,
  workflows, schedules, promotion gates. Designed to be hosted by AgentKit; a local
  runner implements the same contracts.
* Layer 3 - Jev (``hedgefund.jev``): fast typed, calibrated state judgments.

Deterministic code (``policy``, ``risk``, ``execution``, ``portfolio``) owns every
decision that moves capital. No model output can size a position or override a limit.
"""

__version__ = "0.1.0"
