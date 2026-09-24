# botprive

This repository holds three things:

- **Web platform for MetaTrader 5** (`hedgefund/web`, `hedgefund/mt5`, `hedgefund/bots`): a
  secure, responsive dashboard to create bots on any asset your broker offers (gold, Nasdaq,
  crypto, forex, oil…), backtest them, start and stop them, and follow the results live.
  **Guide in French: [docs/PLATFORM.md](docs/PLATFORM.md).** Quick start on Windows:
  `.\deploy\windows\install.ps1`, then
  `.\.venv\Scripts\python.exe -m hedgefund.web create-user --username YOU`, then
  `.\deploy\windows\start.ps1`, and open http://127.0.0.1:8000.
- **`hedgefund/`** is a one-person, 24/7 AI hedge fund. Claude Opus 5.5 does the research,
  an orchestrated set of workflows runs the operation, Jev makes fast typed decisions, and
  deterministic code owns risk and execution. The full design, build plan and risk analysis
  are in **[docs/BLUEPRINT.md](docs/BLUEPRINT.md)**.
- **`app.py`** is the existing ICT Pure Master licence-admin Streamlit app. It's unchanged.

> **Paper mode only.** The config loader refuses `mode: live`. All five strategies sit at
> stage `data`: they're implemented and tested, but none has real-data evidence yet.
> Synthetic backtests show that the system works, not that a strategy makes money.

## Quickstart

```bash
pip install -e ".[research,web,dev]"
pytest -q                                   # all tests
python -m hedgefund validate                # config + 5 strategy specs
python -m hedgefund org                     # departments and workflows
python -m hedgefund backtest --stress       # synthetic backtest of all strategies + stress scenarios
python -m hedgefund backtest --strategy ethbtc_rv --perturb --evidence-out ev.json
python -m hedgefund stages                  # what each strategy needs to advance
python -m hedgefund promote ethbtc_rv --to signal --evidence ev.json   # refused: synthetic evidence
python -m hedgefund recalibrate             # fit + holdout-test + replay a Jev calibration bundle
python -m hedgefund paper --replay 1500 --ephemeral   # offline replay through the 24/7 runner
```

With real data and credentials:

```bash
python -m hedgefund backtest --live-data --days 730          # public Binance/DefiLlama data
export ANTHROPIC_API_KEY=...                                  # or `ant auth login`
python -m hedgefund research scan                             # Opus 5.5: 5-10 opportunities from dated evidence
python -m hedgefund research memo --topic "BTC funding regime" --draft-strategy
python -m hedgefund paper --with-research                     # 24/7 loop (paper venue) + nightly research
```

## Operator controls

| Action | Command |
|---|---|
| Emergency stop (flatten everything) | `python -m hedgefund kill --reason "..."` or `touch var/KILL_SWITCH` |
| Resume after a kill | `python -m hedgefund reset-kill --operator you --reason "..."` |
| See state / pending approvals | `python -m hedgefund status` |
| Daily report | `python -m hedgefund report` |
| Decide a research proposal | `python -m hedgefund approve <request_id> --decision approve --operator you --reason "..."` |
| Promote a strategy | `python -m hedgefund promote <id> --to <stage> --evidence ev.json [--operator you]` |
| Audit | `python -m hedgefund verify-ledger`, `python -m hedgefund calibration` |

## Layout

See [docs/BLUEPRINT.md §4](docs/BLUEPRINT.md#4-repository-structure). In short: `config/`
holds the fund config, risk limits and strategy specs. `hedgefund/` holds the code, split
into core, data, jev, policy, risk, execution, portfolio, strategy, backtest, calibration,
research, orchestration, monitoring, ops, plus the platform (web, mt5, bots). `tests/` covers all of it.

## Not verified

The Jev wire format and the AgentKit API couldn't be checked against official docs from the
build environment. `RemoteJev` refuses to run until you verify its codec and set
`JEV_WIRE_FORMAT_VERIFIED=1`. The live data endpoints haven't been smoke-tested, and the fee
figures are assumptions. Details are in [docs/BLUEPRINT.md §17](docs/BLUEPRINT.md#17-verified-vs-unverified).
