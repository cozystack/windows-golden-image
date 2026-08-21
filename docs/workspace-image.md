# Discovery: Windows + LSEG Workspace image

This document describes the **Discovery track**: a Windows VM running the LSEG Workspace GUI, used interactively to find *which* instruments and datatypes to pull. It does not extract data — that is the headless Airflow pipeline in [`airflow-pipeline.md`](./airflow-pipeline.md).

> The two tracks share one LSEG login. Only one session can be active, so do not keep Workspace signed in on this VM while the extraction pipeline runs (and vice versa). See "single-flight" in the pipeline doc.

## Why a Windows image is still needed

The extraction pipeline is headless and needs no Windows. But it can only pull data whose parameters are already known — the Datastream list mnemonics, instrument identifiers (RIC / ISIN / SEDOL) and datatype codes. Finding those is interactive human work in the Workspace GUI (Datastream Navigator, DFO field lookup); DSWS has no catalogue browser. So Discovery = a person in Workspace deciding *what to pull*; Extraction = the pipeline *pulling it*.

## What the image contains

- **Windows Server 2022** (eval ISO).
- **LSEG Workspace + DFO add-in** — the discovery GUI.
- **Office / Excel** — optional, to sanity-check request forms (DSGRID) before handing parameters to the pipeline.
- **Autologon + RDP** — Workspace needs a logged-in interactive desktop, otherwise it reports "Not Signed In".

No credentials or licences are baked into the image (see [Credentials](#credentials)).

## Build

The image is built with Packer. All build files live next to this doc under [`../images/workspace/`](../images/workspace/); that project's `README.md` has the exact commands. In outline:

1. Stage the Windows Server 2022 eval ISO as a DataVolume (`win2022-iso-dv.yaml`).
2. `packer build` brings up the VM and bakes: Office (Excel), guest config (RDP, no-sleep, session-0 COM fix), and autologon.
3. **Install LSEG Workspace by hand.** Its installer is not silent, so this step is interactive: RDP in, run the public installer (`cdn.refinitiv.com`) through its GUI wizard, sign in once to confirm, sign out.
4. `harden.ps1` (the final provisioner) reverts the build-time WinRM/RDP relaxations (basic + unencrypted off, 5985 rule dropped, NLA on) and strips any baked autologon password.
5. Capture the configured VM as the golden.

### Licensing

The build uses the Windows Server 2022 **evaluation** ISO, and Office is installed via ODT — both fine for building and demoing the image. A **production** Discovery VM needs a **purchased Windows Server licence and an Office/Microsoft 365 licence**; evaluation media is time-limited and not appropriate for production use. LSEG Workspace additionally requires a valid LSEG entitlement.

### Sealing caveat

On the MS eval image `sysprep /generalize` crashes (spopk.dll), so the golden was captured **without** generalize. Clones therefore share the same SID and computer name — acceptable for a single Discovery VM; handle the name per clone if you make several. The seal path is present in the Packer project but disabled by default; `harden.ps1` runs regardless of whether sealing is enabled.

## Register the image in Cozystack

Cozystack offers two ways to make a golden reusable (the generic mechanics belong in the Cozystack docs — this is the client-specific summary):

- **As a cloneable `vm-disk`** (used here): keep the captured disk as a reference `vm-disk`, then create each Discovery VM from a clone of it. Always clone with `cloneType: copy` (not snapshot).
- **As a collection entry** (`vm-default-images`): only fits images reachable by a public HTTP URL, so it suits a *bare* Windows base, not our customized Workspace disk.

## Create and access the VM

- Create a `vm-instance` from a **copy-clone** of the reference disk.
- Access it with `virtctl vnc <vm>` or an RDP port-forward to 3389.
- Autologon lands you on a ready desktop.
- Stop the VM only with `virtctl stop --force` — a graceful ACPI stop does not reliably work on this VM.

## Credentials

- **No LSEG credentials in the image or in git.** Sign in to Workspace by hand with the shared account after the VM is up.
- The build-time Administrator/WinRM password is a throwaway placeholder in the answer files.
- **Autologon password is not baked.** It is written only if injected at build time, and `harden.ps1` strips any `DefaultPassword` as the final step; inject it at deploy (or use Sysinternals `Autologon.exe`).
- **WinRM/RDP are hardened before capture.** The build relaxes them so Packer can connect; `harden.ps1` reverts basic/unencrypted, drops the 5985 rule, and re-enables NLA, so those relaxations do not ship.

## Session fragility

Workspace holds an interactive session. Locking the screen or dropping the RDP connection can flip it to "Not Signed In". Recover by returning the session to the console with `tscon` and signing back in. Because the login is shared and single-active, coordinate with the extraction pipeline so both never hold it at once.

## Handoff to extraction

Discovery produces parameters, not data. Record the instruments/lists and datatypes you found into the **Request Table** workbook (first sheet: country → instruments → datatypes). `hack/request_table.py` (in the pipeline repo) then converts that workbook into the `config.json` the DAGs consume. From there the extraction pipeline takes over.
