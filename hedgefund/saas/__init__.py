"""Alpha Edge SaaS: trading journal, ICT analysis, risk guard and AI agents for members.

Design: docs/CONCEPTION.md (kept out of the public repository). Deterministic engines compute
every number; LLM agents only explain, prioritise and propose. Every tenant's data is scoped in
code (``Database.tenant``) and, on PostgreSQL, by row-level security as well.
"""
