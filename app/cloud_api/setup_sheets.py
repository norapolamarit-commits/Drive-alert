"""Initialize the two private Doz storage tabs in an existing spreadsheet."""

import os
import sys
from urllib.parse import quote

from sheets_storage import HEADERS, SheetsStorageError, store_from_env


def main() -> int:
    store = store_from_env()
    if store is None:
        print("Set DOZ_SHEETS_SPREADSHEET_ID and DOZ_GOOGLE_SERVICE_ACCOUNT_JSON first.")
        return 2
    try:
        metadata = store._request("GET", store.base, params={"fields": "sheets.properties.title"})
        titles = {sheet.get("properties", {}).get("title") for sheet in metadata.get("sheets", [])}
        for tab in ("SensorEvents", "AlertEvents"):
            if tab not in titles:
                store._request("POST", f"{store.base}:batchUpdate",
                               json={"requests": [{"addSheet": {"properties": {"title": tab}}}]})
            encoded = quote(f"{tab}!A1:D1", safe="")
            current = store._request("GET", f"{store.base}/values/{encoded}").get("values", [])
            if current and current[0] != HEADERS:
                raise SheetsStorageError(f"{tab} has unexpected headers; refusing to overwrite")
            if not current:
                store._request("PUT", f"{store.base}/values/{encoded}",
                               params={"valueInputOption": "RAW"},
                               json={"majorDimension": "ROWS", "values": [HEADERS]})
        print("SensorEvents and AlertEvents are ready. No health data was written.")
        return 0
    except SheetsStorageError:
        print("Could not initialize tabs. Check sharing, API access, and empty tab headers.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
