param([switch]$Status)
$repo = git rev-parse --show-toplevel 2>$null
if (-not $repo) {
  Write-Host 'No git repository here. Run git init first, then run this script again.' -ForegroundColor Yellow
  exit 2
}
$repo = $repo.Trim()
$hooks = Join-Path $repo '.githooks'
if (-not (Test-Path (Join-Path $hooks 'pre-commit'))) {
  Write-Host "pre-commit hook missing at $hooks" -ForegroundColor Red
  exit 1
}
if ($Status) {
  $cur = git config --get core.hooksPath 2>$null
  Write-Host "repo=$repo hooksPath=$cur"
  exit 0
}
git config core.hooksPath '.githooks'
$cur = git config --get core.hooksPath 2>$null
Write-Host "hooks installed: core.hooksPath=$cur" -ForegroundColor Green
Write-Host 'The pre-commit hook now runs find-sensitive.ps1 against the whole tree on every commit.'
exit 0
