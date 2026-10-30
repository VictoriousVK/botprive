from __future__ import annotations

import pytest

from hedgefund.config import load_config
from hedgefund.core.clock import SimClock
from hedgefund.core.ledger import Ledger
from hedgefund.data.synthetic import generate_market_data
from hedgefund.strategy.spec import load_specs


@pytest.fixture(scope="session")
def cfg():
    return load_config()


@pytest.fixture(scope="session")
def specs(cfg):
    return {s.id: s for s in load_specs(cfg.strategy_dir)}


@pytest.fixture(scope="session")
def data():
    return generate_market_data(n_bars=1600, seed=11)


@pytest.fixture
def ledger():
    led = Ledger(":memory:")
    yield led
    led.close()


@pytest.fixture
def clock():
    return SimClock(1_700_000_000_000)
