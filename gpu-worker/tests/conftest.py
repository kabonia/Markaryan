import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import os


def pytest_runtest_logreport(report):
    """Ошибки тестов — аннотациями GitHub: видно на странице запуска без скачивания журнала."""
    if report.failed and os.environ.get("GITHUB_ACTIONS"):
        text = str(report.longrepr).strip().splitlines()
        tail = " | ".join(line.strip() for line in text[-12:] if line.strip())
        print(f"::error title={report.nodeid.split('::')[-1]}::{tail[:1500]}")
