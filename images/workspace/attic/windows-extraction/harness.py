"""
harness.py — headless Excel refresh driver for the Nuvolos DFO pipeline.

Opens a workbook over COM, refreshes it, saves, and RELIABLY tears down Excel.
Runs chunked + resumable via a checkpoint file.

DFO notes (learned the hard way — see README):
  * Excel must be VISIBLE and in an INTERACTIVE (autologon) session — the DFO
    add-in is a GUI add-in and deadlocks with Visible=False / Session-0.
  * EnableEvents=False before Open, so the workbook's own Workbook_Open macro does
    NOT run (the customer book's VBA targets an old Datastream API -> run-time 438
    and a modal error dialog that hangs headless automation).
  * Refresh via the add-in's PowerlinkCOMAddIn.COMAddIn.RefreshWorkbook() (bypasses
    the book's broken VBA), then poll the REQUEST_TABLE Status column.

Refresh methods:
  refreshall : Workbook.RefreshAll + wait for async queries  (generic / non-DFO)
  dfo        : PowerlinkCOMAddIn.COMAddIn.RefreshWorkbook() + poll REQUEST_TABLE STATUS
"""
import argparse, collections, json, os, subprocess, time


def kill_excel():
    subprocess.run(["taskkill", "/f", "/im", "EXCEL.EXE"], capture_output=True)


def _poll_status(wb, timeout):
    """Poll the REQUEST_TABLE Status column, logging the value distribution until
    it stops changing (refresh done) or timeout."""
    ws = None
    for sh in wb.Worksheets:
        if str(sh.Name).strip().upper() == "REQUEST_TABLE":
            ws = sh; break
    if ws is None:
        print("REQUEST_TABLE sheet not found; skipping status poll", flush=True); return
    used = ws.UsedRange
    nrows, ncols = used.Rows.Count, used.Columns.Count
    status_col = header_row = None
    for r in range(1, min(6, nrows) + 1):
        for c in range(1, min(40, ncols) + 1):
            v = ws.Cells(r, c).Value
            if v is not None and str(v).strip().lower() == "status":
                status_col, header_row = c, r; break
        if status_col:
            break
    if not status_col:
        print("Status column not found in REQUEST_TABLE header", flush=True); return
    print(f"polling STATUS col={status_col} rows {header_row+1}..{nrows}", flush=True)
    import pythoncom
    last_done = -1; stable = 0; deadline = time.time() + timeout
    # DFO ProcessRequestTable is ASYNC: it returns immediately and fills the STATUS
    # column (OK / ERROR...) request-by-request over time. Completion = the done count
    # (OK+ERROR) stops rising AND nothing is left in-progress. NEVER treat all-empty as
    # done — that just means it has not started / the first (slow) request is running.
    while time.time() < deadline:
        try:
            pythoncom.PumpWaitingMessages()   # let Excel's async callbacks run
        except Exception:
            pass
        vals = ws.Range(ws.Cells(header_row + 1, status_col),
                        ws.Cells(nrows, status_col)).Value
        counts = collections.Counter()
        for row in (vals or []):
            v = row[0] if isinstance(row, (list, tuple)) else row
            counts[str(v).strip() if v not in (None, "") else "<empty>"] += 1
        ok = counts.get("OK", 0)
        err = sum(v for k, v in counts.items() if "ERROR" in k.upper())
        empty = counts.get("<empty>", 0)
        pending = sum(counts.values()) - ok - err - empty      # non-empty, non-terminal
        done = ok + err
        print("STATUS: OK=%d ERROR=%d pending=%d empty=%d | %s" % (
            ok, err, pending, empty,
            ", ".join("%s=%d" % (k, v) for k, v in counts.most_common(6))), flush=True)
        if done > 0 and pending == 0:            # some requests done, none in progress
            if done == last_done:
                stable += 1
            else:
                stable, last_done = 0, done
            if stable >= 4:                       # ~80s with no new completions
                print("STATUS: complete (%d done, no pending)" % done, flush=True); break
        else:
            stable = 0
        time.sleep(20)


def refresh_workbook(path, method="refreshall", timeout=14400, save=True):
    import pythoncom
    import win32com.client as win32
    pythoncom.CoInitialize()
    # gencache.EnsureDispatch (early-bound), NOT DispatchEx: the makepy proxy is what
    # lets the DFO add-in's injected members resolve. The LSEG forum fix for
    # "Method or data member not found" / "COMAddin not showing" (community.developers
    # .lseg.com 100562, 101389) is: build the typed proxy AND enumerate COMAddIns
    # (touch .Description/.Connect) BEFORE opening the workbook, so the refinitiv-shim
    # fully initializes. Skip either and the workbook's DFO VBA fails to COMPILE.
    excel = win32.gencache.EnsureDispatch("Excel.Application")
    excel.Visible = True            # DFO add-in needs a visible/interactive Excel
    excel.DisplayAlerts = False
    excel.AskToUpdateLinks = False
    excel.EnableEvents = False       # do NOT run the workbook's Workbook_Open (438)
    try:
        # --- initialize the DFO add-in BEFORE the workbook (see note above) ---
        for a in excel.COMAddIns:
            try:
                _ = a.Description          # touch it -> forces shim load
                if a.ProgId in ("PowerlinkCOMAddIn.COMAddIn", "DFOAddInExcel2010") and not a.Connect:
                    a.Connect = True
            except Exception:
                pass
        wb = excel.Workbooks.Open(os.path.abspath(path), UpdateLinks=0)
        print(f"opened: {wb.Worksheets.Count} sheets", flush=True)
        # Re-enable events AFTER open: Workbook_Open is already past (suppressed above),
        # but the DFO async Request-Table processor drives itself through Excel events /
        # callbacks — with events off it returns and then never resumes (STATUS stays empty).
        excel.EnableEvents = True
        if method == "dfo":
            # The DFO Request Table processor is the workbook's DFO-injected VBA:
            #   Public Sub ProcessRequestTable(...all optional...)  in module basProcessTable
            # (exactly what the "Process Table" button, btnProcessTable_Click, runs).
            # Invoke it workbook-qualified. Needs macros ENABLED + EnableEvents=False so
            # the DFO macro runs while the workbook's own Workbook_Open (438) does not.
            macro = "'%s'!ProcessRequestTable" % wb.Name
            print("DFO add-in connected; running " + macro, flush=True)
            excel.Application.Run(macro)
            print("ProcessRequestTable returned; polling STATUS", flush=True)
            _poll_status(wb, timeout)
        else:
            wb.RefreshAll()
            excel.CalculateUntilAsyncQueriesDone()
            deadline = time.time() + timeout
            while excel.CalculationState != 0 and time.time() < deadline:
                time.sleep(2)
        if save:
            print("saving...", flush=True)
            wb.Save()
        wb.Close(SaveChanges=False)
        return True
    finally:
        try:
            excel.Quit()
        except Exception:
            pass
        del excel
        pythoncom.CoUninitialize()
        time.sleep(1)
        kill_excel()   # belt-and-suspenders: COM Quit often leaves a zombie


def run_chunked(workbooks, method="refreshall",
                checkpoint="C:/poc/checkpoint.json", retries=2, timeout=14400):
    done = set()
    if os.path.exists(checkpoint):
        try:
            done = set(json.load(open(checkpoint)).get("done", []))
        except Exception:
            done = set()
    ok = 0
    for wb in workbooks:
        if wb in done:
            print(f"skip (checkpointed): {wb}"); ok += 1; continue
        for attempt in range(1, retries + 2):
            try:
                print(f"refresh {wb} (attempt {attempt}) ...", flush=True)
                refresh_workbook(wb, method=method, timeout=timeout)
                done.add(wb); ok += 1
                json.dump({"done": sorted(done)}, open(checkpoint, "w"))
                print(f"  ok: {wb}", flush=True)
                break
            except Exception as e:
                print(f"  FAILED attempt {attempt}: {e}", flush=True)
                kill_excel(); time.sleep(3)
                if attempt == retries + 1:
                    print(f"  giving up: {wb}", flush=True)
    print(f"DONE {ok}/{len(workbooks)}", flush=True)
    return ok == len(workbooks)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("workbooks", nargs="+", help="workbook paths (one per chunk)")
    ap.add_argument("--method", choices=["refreshall", "dfo"], default="refreshall")
    ap.add_argument("--checkpoint", default="C:/poc/checkpoint.json")
    ap.add_argument("--timeout", type=int, default=14400, help="per-workbook seconds")
    args = ap.parse_args()
    ok = run_chunked(args.workbooks, method=args.method,
                     checkpoint=args.checkpoint, timeout=args.timeout)
    raise SystemExit(0 if ok else 1)
