import os
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal

import pytest

import main
import day_trade_store as store
import day_trade_daily as daily
import web_app


@pytest.fixture(autouse=True)
def database(tmp_path, monkeypatch):
    monkeypatch.setenv('DATABASE_URL', '')
    monkeypatch.setenv('INVESTMENT_DATABASE_URL', '')
    monkeypatch.setattr(main, 'INVESTMENT_DATA_DIR', tmp_path)
    monkeypatch.setattr(main, 'INVESTMENT_DB_PATH', tmp_path / 'trade.db')
    monkeypatch.setattr(main, 'LEGACY_INVESTMENT_DB_PATH', tmp_path / 'legacy.db')
    store.ensure_day_trade_db()


def operation(date='2026-09-25'):
    return web_app.validated_day_trade_payload(dict(trade_date=date,
        entry_time='10:30', asset='WINV26', market='Mini índice', direction='Compra',
        quantity=2, entry_price_text='135000', stop_price_text='134900',
        target_price_text='135200', strategy='Teste', operation_result='Gain', costs_text='5'))


def test_persistence_totals_and_correction_history():
    owner = store.DEFAULT_OWNER_KEY
    store.save_initial_capital('1000', owner)
    store.create_operation(operation(), owner)  # 80 gross - 5 costs
    daily.save(owner, '2026-09-28', '1.250,50', 'Custos descontados', 0)
    daily.save(owner, '2026-09-29', '-350,00', '', 0)
    daily.save(owner, '2026-09-30', '0', '', 0)
    payload = store.build_payload('2026-09-28', owner)
    assert payload['items'] == []
    assert payload['summary']['net_result'] == 1250.5
    assert payload['summary']['operation_count'] == 0
    assert payload['summary']['gains'] == 0
    assert len(store.build_bi_payload('2026-09-01', '2026-09-30', owner)['daily_results']) == 3
    assert store.operations_net_result(owner) == Decimal('975.50')
    assert Decimal(store.capital_summary(owner)['capital_text']) == Decimal('1975.50')
    daily.save(owner, '2026-09-28', '250,50', 'Corrigido', 1)
    daily.save(owner, '2026-09-28', '250,50', 'Corrigido', 1)  # retry
    assert store.operations_net_result(owner) == Decimal('-24.50')
    statement = store.capital_statement(owner)
    assert Decimal(statement['capital_text']) == Decimal('975.50')
    assert Decimal(statement['statement_entries'][-1]['balance_text']) == Decimal('975.50')
    assert len([e for e in statement['statement_entries'] if e['type'] == 'day_trade_daily_result']) == 3
    with sqlite3.connect(main.INVESTMENT_DB_PATH) as db:
        assert db.execute('SELECT count(*) FROM day_trade_daily_history WHERE trade_date = ?', ('2026-09-28',)).fetchone()[0] == 2


def test_modes_are_exclusive_in_both_directions_and_when_moving_operation():
    owner = store.DEFAULT_OWNER_KEY
    ident = store.create_operation(operation(), owner)
    with pytest.raises(ValueError, match='operações individuais'):
        daily.save(owner, '2026-09-25', '100', '', 0)
    daily.save(owner, '2026-09-28', '0', '', 0)
    with pytest.raises(ValueError, match='consolidado'):
        store.create_operation(operation('2026-09-28'), owner)
    with pytest.raises(ValueError, match='consolidado'):
        store.update_operation(str(ident), operation('2026-09-28'), owner)
    assert len(store.list_operations('2026-09-25', owner)) == 1
    assert store.list_operations('2026-09-28', owner) == []


@pytest.mark.parametrize('amount', ['', None, 'abc', 'NaN', 'Infinity', '-Infinity', '1,234', '9999999999999999'])
def test_invalid_amount_is_not_saved(amount):
    with pytest.raises(ValueError):
        daily.save('owner', '2026-09-28', amount, '', 0)
    assert daily.list_results('owner') == []


def test_owner_isolation_and_stale_revision():
    daily.save('one', '2026-09-28', '100', '', 0)
    daily.save('two', '2026-09-28', '-200', '', 0)
    with pytest.raises(ValueError, match='outra sessão'):
        daily.save('one', '2026-09-28', '300', '', 0)
    assert store.operations_net_result('one') == Decimal('100')
    assert store.operations_net_result('two') == Decimal('-200')
    assert daily.list_results('three') == []


def test_simultaneous_modes_cannot_double_count():
    def run(which):
        try:
            if which == 'daily':
                daily.save('owner', '2026-09-25', '200', '', 0)
            else:
                store.create_operation(operation(), 'owner')
            return True
        except ValueError:
            return False
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(run, ['daily', 'operation']))
    assert sum(results) == 1
    assert store.operations_net_result('owner') in (Decimal('200'), Decimal('75'))


def test_api_save_reload_and_access_control(monkeypatch):
    import asyncio
    import httpx

    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=web_app.app), base_url='http://test') as client:
            payload = dict(trade_date='2026-09-28', net_result_text='-25,50', expected_revision=0)
            monkeypatch.setattr(web_app, 'authenticated_user', lambda scope: None)
            monkeypatch.setattr(web_app, 'has_valid_budget_api_session', lambda scope: False)
            assert (await client.put('/api/day-trade/daily-result', json=payload)).status_code == 401
            monkeypatch.setattr(web_app, 'authenticated_user', lambda scope: {'role': 'viewer'})
            assert (await client.put('/api/day-trade/daily-result', json=payload)).status_code == 403
            monkeypatch.setattr(web_app, 'authenticated_user', lambda scope: {'role': 'owner'})
            monkeypatch.setattr(web_app, 'has_valid_budget_api_session', lambda scope: True)
            result = await client.put('/api/day-trade/daily-result', json=payload)
            assert result.status_code == 200
            assert result.json()['daily_result']['net_result'] == -25.5
            assert (await client.get('/api/day-trade?date=2026-09-28')).json()['summary']['net_result'] == -25.5
            assert (await client.get('/api/day-trade/navigation')).json()['daily_results'][0]['net_result'] == -25.5
            assert (await client.get('/api/day-trade/bi?from=2026-09-01&to=2026-09-30')).json()['daily_results'][0]['net_result'] == -25.5
    asyncio.run(run())
