"""The reward watch of SasBoatFixes, run inside Python against a stand-in for the game."""

from __future__ import annotations

from pathlib import Path

import pytest
from lupa import LuaRuntime

SCRIPT = Path(__file__).resolve().parents[1] / "SasBoatFixes" / "Scripts" / "main.lua"

STUB = r"""
Printed = {}
print = function(text) Printed[#Printed + 1] = text end
Timers = {}
function LoopInGameThreadWithDelay(ms, fn) Timers[#Timers + 1] = { ms = ms, fn = fn } end
Hooks = {}
function RegisterHook(path, fn) Hooks[path] = fn end
function RegisterKeyBind() end
function NotifyOnNewObject() end
function FindAllOf(class) if class == "FinanceComponent" then return PyFinance() end return nil end
function FindFirstOf() return nil end
function StaticFindObject() return nil end
function FName(text) return text end
Key = setmetatable({}, { __index = function(_, name) return name end })
ModifierKey = setmetatable({}, { __index = function(_, name) return name end })
"""

HOOK = "/Game/ShipsAtSea/UI/Missions/WBP_MissionSuccess.WBP_MissionSuccess_C:SetReceivedRewards"


class Param:
    """What a hook callback is given: the value behind :get()."""

    def __init__(self, value):
        self.value = value

    def get(self):
        return self.value


class Text:
    def __init__(self, text):
        self.text = text

    def ToString(self):
        return self.text

    def GetText(self):
        return self


class Widget:
    def __init__(self, title, short_id):
        self.MissionTitle = Text(title)
        self.ShortID = Text(short_id)


class Kind:
    def __init__(self, name):
        self.name = name

    def GetFName(self):
        return Text(self.name)


class Received:
    def __init__(self, kind, amount, stage):
        self.RewardType, self.amount, self.RewardsDescription = Kind(kind), amount, Text(stage)


class Array:
    def __init__(self, items):
        self.items = items

    def ForEach(self, fn):
        for index, item in enumerate(self.items):
            fn(index + 1, Param(item))


class Decimal:
    def __init__(self, raw):
        self.Value = raw


class Tx:
    def __init__(self, raw, text):
        self.Value, self.Description = Decimal(raw), Text(text)
        self.Date = type("D", (), {"Day": type("Day", (), {"Day": 5})(), "Month": 8})()


class Finance:
    """A finance component whose capital the test can change."""

    def __init__(self):
        self.Capital = Decimal(300000000)
        self.Ledger = type("L", (), {"Transactions": Array([Tx(2561500, "Job Payment")])})()

    def GetFullName(self):
        return "FinanceComponent /Game/Map.Map:Level.BP_Company_C.Finance"

    def GetOwner(self):
        return type("Owner", (), {"GetClass": lambda s: Kind("BP_Company_C")})()


@pytest.fixture
def watch():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUB)
    finance = Finance()
    g = lua.globals()
    g.PyFinance = lambda: lua.table_from([finance])
    g.SAS_TEST = True
    lua.execute(SCRIPT.read_text(encoding="utf-8"))
    one_second = next(g.Timers[i]["fn"] for i in range(1, len(g.Timers) + 1) if g.Timers[i]["ms"] == 1000)
    one_second()  # the first look hooks the completion screen
    return type("Watch", (), {"lua": lua, "g": g, "finance": finance, "tick": staticmethod(one_second)})


def lines(w):
    return [w.g.Printed[i] for i in range(1, len(w.g.Printed) + 1) if "REWARD" in w.g.Printed[i]]


def test_money_is_written_in_kroner_with_spaces(watch):
    assert watch.g.Krone(2561500) == "25 615.00"
    assert watch.g.Krone(-5) == "-0.05"
    assert watch.g.Krone(100) == "1.00"
    assert watch.g.Krone(123456789) == "1 234 567.89"


def test_the_completion_screen_is_hooked(watch):
    assert HOOK in dict(watch.g.Hooks.items())


def test_a_screen_with_rewards_is_written_with_the_balance(watch):
    rewards = Array([Received("MissionReward_Money_0", 25615, "Cargo loaded"), Received("MissionReward_XP_1", 237, "Cargo loaded")])
    watch.g.Hooks[HOOK](Param(Widget("2 Medium goods to Mosken", "#DL-1234")), Param(rewards))
    [line] = lines(watch)
    assert 'REWARD: the completion screen for "2 Medium goods to Mosken" #DL-1234 lists 2 reward(s)' in line
    assert "MissionReward_Money_0 25 615.00 (Cargo loaded)" in line and "MissionReward_XP_1 237 (Cargo loaded)" in line
    assert "(money 25 615.00)" in line and "balance 3 000 000.00" in line


def test_a_screen_without_rewards_says_so(watch):
    watch.g.Hooks[HOOK](Param(Widget("5 Medium goods to Å", "#DL-9")), Param(Array([])))
    [line] = lines(watch)
    assert 'lists NO rewards' in line and "#DL-9" in line


def test_the_balance_is_checked_again_and_reported_with_the_ledger(watch):
    watch.g.Hooks[HOOK](Param(Widget("T", "#1")), Param(Array([Received("MissionReward_Money_0", 100, "")])))
    watch.finance.Capital = Decimal(300000000 + 10000)  # 100.00 NOK arrived after the screen
    watch.g.SasTest.DueNow()
    watch.tick()
    later = lines(watch)[1:]
    assert len(later) == 2  # the checks 5 and 60 seconds after the screen
    assert "5 s after the screen the balance has changed by 100.00 (shown money 100.00)" in later[0]
    assert "60 s after the screen" in later[1]
    assert "5/9 Job Payment 25 615.00" in later[0]  # the newest ledger line


def test_a_reward_that_did_not_arrive_shows_as_no_change(watch):
    watch.g.Hooks[HOOK](Param(Widget("T", "#1")), Param(Array([Received("MissionReward_Money_0", 500, "")])))
    watch.g.SasTest.DueNow()
    watch.tick()
    assert "has changed by 0.00 (shown money 500.00)" in lines(watch)[1]
