# Sobelow Ignore Justifications

All ignored checks are by design, not bugs. Each has been reviewed.

## Config.CSRF
**Files:** `lib/ex_gocd_web/router.ex`
- `:api` pipeline uses `TokenAuthPlug` (bearer token authentication), not session cookies. CSRF attacks require session cookies — tokens are immune.
- `:agent_remoting` pipeline handles agent communication via agent-specific cookie auth. Agents are CLI processes, not browsers.

## Config.HTTPS
**Scope:** Global
- HTTPS is a deployment/infrastructure concern (reverse proxy, load balancer). The application itself runs HTTP and is fronted by nginx/ALB in production.

## Config.CSP
**Scope:** Global
- Content Security Policy headers are not required for a CI/CD server dashboard. Added value is minimal vs complexity of maintaining a correct CSP for dynamic LiveView content.

## Traversal.FileModule
**Files:** `lib/ex_gocd_web/controllers/artifacts_controller.ex`, `lib/ex_gocd/artifact_cleanup.ex`
- **artifacts_controller.ex**: All file paths are validated upstream via `check_safe_segments/1` (rejects `..`, `/`, `\`) and `check_boundary/2` (ensures path stays within job directory). Agent-uploaded files go through Zip Slip protection in `extract_zip_securely/2`.
- **artifact_cleanup.ex**: `File.rm_rf` operates on paths built from database values (pipeline name, counter, stage name, counter) — never from user input. Safe by design.

## Traversal.SendFile
**Files:** `lib/ex_gocd_web/controllers/artifacts_controller.ex`
- `send_file` serves artifact files after `check_safe_segments` and `check_boundary` validation. Path traversal already prevented.

## XSS.SendResp
**Files:** `lib/ex_gocd_web/controllers/artifacts_controller.ex`
- `send_resp` serves `application/zip` binary content (not HTML). No XSS vector exists for binary zip responses.
