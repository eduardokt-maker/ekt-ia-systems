import gc
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main
import day_trade_store
import web_app

class FuturesPersistenceTest(unittest.TestCase):
    def test_create_edit_and_reload_both_contracts(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'DATABASE_URL': '', 'INVESTMENT_DATABASE_URL': ''}), patch.object(main, 'INVESTMENT_DATA_DIR', Path(tmp)), patch.object(main, 'INVESTMENT_DB_PATH', Path(tmp)/'trades.db'), patch.object(main, 'LEGACY_INVESTMENT_DB_PATH', Path(tmp)/'legacy.db'):
            source = dict(trade_date='2026-09-09', entry_time='10:30', asset='WDOV26', market='Mini dólar', direction='Compra', quantity=3, entry_price_text='5430', stop_price_text='5420', target_price_text='5440', point_value_text='999', strategy='Teste', operation_result='Gain', costs_text='5')
            ident = day_trade_store.create_operation(web_app.validated_day_trade_payload(source))
            saved = day_trade_store.list_operations('2026-09-09')[0]
            self.assertEqual((saved['points_result'],saved['planned_risk'],saved['potential_gain'],saved['gross_result'],saved['net_result']), (10,300,300,300,295))
            source.update(direction='Venda', stop_price_text='5440', target_price_text='5420', operation_result='stop loss', quantity=2)
            self.assertTrue(day_trade_store.update_operation(str(ident), web_app.validated_day_trade_payload(source)))
            saved = day_trade_store.list_operations('2026-09-09')[0]
            self.assertEqual((saved['points_result'],saved['gross_result'],saved['net_result']), (-10,-200,-205))
            source.update(asset='WINV26',market='Mini índice',direction='Compra',entry_price_text='135000',stop_price_text='134900',target_price_text='135200',operation_result='Gain')
            self.assertTrue(day_trade_store.update_operation(str(ident), web_app.validated_day_trade_payload(source)))
            saved = day_trade_store.list_operations('2026-09-09')[0]
            self.assertEqual((saved['points_result'],saved['gross_result'],saved['net_result']), (200,80,75))

            gc.collect()
