from __future__ import annotations

import argparse
import json
import os
from datetime import date, timedelta

import capital_flow_b3


def main() -> None:
    parser = argparse.ArgumentParser(description="Coleta oficial do fluxo de investidores B3")
    parser.add_argument("--start", default=os.getenv("B3_FLOW_START_DATE", "2026-04-01"))
    parser.add_argument("--end", default=date.today().isoformat())
    parser.add_argument("--reconcile", type=int, default=0, help="Reprocessa aproximadamente os últimos N pregões")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    start = args.start
    if args.reconcile:
        start = (date.today() - timedelta(days=max(14, args.reconcile * 2))).isoformat()
    result = capital_flow_b3.sync_official_data(start, args.end, force=args.force or bool(args.reconcile))
    print(json.dumps(result, ensure_ascii=False, default=str))


if __name__ == "__main__":
    main()
