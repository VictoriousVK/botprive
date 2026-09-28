"""MCP servers over the same tool registry as the agents (docs/SAAS.md): journal, ict-engine,
knowledge, market-data, risk. Run on stdio for Claude Code or another MCP client:

    python -m hedgefund.saas mcp journal --tenant t_m1 --user 1

The tenant and the user are fixed by the operator on the command line; the model never passes
them, and a server only exposes the tools of its prefix. Every call goes through the harness
(validation, timeout, budget, tool-output guardrail)."""

from __future__ import annotations

import json
from typing import Any

from hedgefund.saas.harness import Budget
from hedgefund.saas.tools import ToolContext

SERVERS = {
    "journal": ("journal.", "perf."),
    "ict-engine": ("ict.",),
    "knowledge": ("knowledge.",),
    "risk": ("risk.",),
    "market-data": ("ict.",),
}


def build_server(saas: Any, server: str, tenant_id: str, user_id: int, entitlements: frozenset[str] = frozenset({"journal", "academy_member", "analyses", "performance", "lab"})) -> Any:
    from mcp.server.mcpserver import MCPServer

    if server not in SERVERS:
        raise ValueError(f"serveur inconnu : {server} ({', '.join(SERVERS)})")
    if not tenant_id or user_id <= 0:
        raise ValueError("précisez --tenant et --user : l'isolation des clients ne dépend jamais du modèle")
    mcp = MCPServer(f"alpha-edge-{server}")
    prefixes = SERVERS[server]
    for name, tool in saas.tools.tools.items():
        if not name.startswith(prefixes):
            continue

        def make(tool_name: str, model: type):
            def fn(args):  # annotations set below (module uses postponed evaluation)
                ctx = ToolContext(saas.db, tenant_id, user_id, budget=Budget(max_tool_calls=1, deadline_s=30), services=saas, entitlements=entitlements)
                return json.dumps(saas.tools.invoke(ctx, tool_name, args.model_dump()), ensure_ascii=False, default=str)

            fn.__name__ = tool_name.replace(".", "_")
            fn.__annotations__ = {"args": model, "return": str}
            return fn

        mcp.add_tool(make(name, tool.input_model), name=name.replace(".", "_"), description=tool.description)
    return mcp


def serve(saas: Any, server: str, tenant_id: str, user_id: int) -> int:
    build_server(saas, server, tenant_id, user_id).run("stdio")
    return 0
