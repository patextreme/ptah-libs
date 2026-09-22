--!strict
-- Factory workflow: the autonomous issue → reviewed PR loop, config only.
--
-- The whole orchestration — claiming the oldest eligible issue, provisioning
-- its `issue-<n>` worktree off `origin/<base>`, resolving the openspec
-- change or editing directly, driving groom → implement → verify, opening
-- the issue-linked PR, the convergent review loop, and the teardown — is
-- the library's factory playbook (`playbooks/factory/`, see its README for
-- the outcome taxonomy, the laws, and the environment requirements). This
-- shim is Local config and nothing else; a tag bump converges it with the
-- other consumers' shims.
--
-- Environment: the `pi` agent (from the ptah agent registry) must resolve,
-- `gh` must be authenticated, `git` must be on PATH, and `openspec` must be
-- on PATH for the lifecycle steps.

-- This repo is the library itself: there is no generated
-- `luau_packages/ptah_libs` shim, so require the package entry through the
-- root `.luaurc` alias (the same way the ad-hoc dev workflows under
-- `.ptah/workflows/adhoc/` do).
local libs = require("@ptah_libs/lib")

-- ---------------------------------------------------------------------------
-- Local config
-- ---------------------------------------------------------------------------

-- The repo-configured queue label: a human's assertion that an issue is
-- ready for development. Required, no default.
local QUEUE_LABEL = "ai-r4d"

-- The base every issue's worktree branches from and every PR targets
-- (required, no default).
local BASE = "main"

local MODEL = "zai/glm-5.3-flash"

local workConfig = { { id = "model", value = MODEL } }

-- Repo knowledge travels as free-text prompt fragments; the library-owned
-- prompt skeletons place them at their declared injection points.
local CONVENTIONS = [[
Read CONTEXT.md for the vocabulary before editing. Every module is
--!strict and the compatibility gate is `ptah check`: before finishing, run
`ptah check` on the touched entry scripts (a workflow shim or `lib.luau`)
and resolve every reported finding.]]

local PR_CONTRACT = [[
Keep Conventional Commits titles that reference the issue. The pull request
opens against main automatically; its body carries `Closes #<n>`. Do not
restate CI rules here — the repository's gates are the ones the review loop
runs.]]

local factory = libs.factory.new({
	agent = ptah.agent("pi"),
	judgeAgent = ptah.agent("pi"),
	reporterAgent = ptah.agent("pi"),
	sessionConfig = workConfig,
	judgeSessionConfig = workConfig,
	reporterSessionConfig = workConfig,
	queueLabel = QUEUE_LABEL,
	base = BASE,
	conventions = CONVENTIONS,
	prContract = PR_CONTRACT,
	maxReviewIterations = 10,
})

factory:drain()
