# =====================================================================
# Apply-AuthLocalStoragePatch.ps1
# ---------------------------------------------------------------------
# Applies four targeted edits to index.html:
#   1. Hydrate auth state (token, role, authed) from localStorage on mount
#   2. Persist token + role to localStorage on successful login
#   3. Clear token + role from localStorage on Sign Out
#   4. Guard Save Quote and Generate AI Proposal against empty token
#
# SAFETY:
#   - Verifies baseline MD5 BEFORE any modification
#   - Aborts cleanly on any failure WITHOUT modifying the file
#   - Verifies all four patches applied at the end
#   - Reports clear SUCCESS / FAILURE with details
#
# USAGE:
#   PS> Set-Location C:\Users\marca\nexuspay-paycalculator-frontend
#   PS> .\Apply-AuthLocalStoragePatch.ps1
# =====================================================================

$ErrorActionPreference = "Stop"

$Target = ".\index.html"
$ExpectedBaselineMd5 = "E179349F08EF22D38E50660CD2B0B372"
$ExpectedBaselineBytes = 100802
$ExpectedFinalBytes = 101803

function Write-Step($msg)    { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Pass($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg)    { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Yellow }

Write-Section "PRE-FLIGHT CHECKS"

if (-not (Test-Path $Target)) {
    Write-Fail "index.html not found in current directory."
    Write-Fail "Are you in C:\Users\marca\nexuspay-paycalculator-frontend ?"
    exit 1
}
Write-Pass "index.html exists"

$baselineSize = (Get-Item $Target).Length
if ($baselineSize -ne $ExpectedBaselineBytes) {
    Write-Fail "index.html is $baselineSize bytes; expected $ExpectedBaselineBytes."
    Write-Fail "File is not at the known-good baseline. Restore from index.html.backup-step8 first."
    exit 1
}
Write-Pass "index.html is exactly $ExpectedBaselineBytes bytes (baseline match)"

$baselineMd5 = (Get-FileHash $Target -Algorithm MD5).Hash
if ($baselineMd5 -ne $ExpectedBaselineMd5) {
    Write-Fail "MD5 mismatch."
    Write-Fail "Got:      $baselineMd5"
    Write-Fail "Expected: $ExpectedBaselineMd5"
    Write-Fail "File contents have been modified. Restore from backup first."
    exit 1
}
Write-Pass "MD5 hash matches baseline ($baselineMd5)"

Write-Section "READING FILE"
$content = [System.IO.File]::ReadAllText((Resolve-Path $Target).Path, [System.Text.UTF8Encoding]::new($false))
Write-Pass "Read $($content.Length) characters"

Write-Section "APPLYING PATCHES"

# ----- PATCH 1: hydrate auth state from localStorage -----
$p1_old = @'
function App(){
  const[authed,setAuthed]=useState(false),[token,setToken]=useState(""),[role,setRole]=useState("");
  const[email,setEmail]=useState(""),[pass,setPass]=useState(""),[loginErr,setLoginErr]=useState(""),[logging,setLogging]=useState(false);
'@

$p1_new = @'
function App(){
  // -- Auth state -- hydrate from localStorage so token survives re-renders, F12, refresh, and tab navigation --
  const _lsGet=(k,d)=>{try{const v=window.localStorage.getItem(k);return v===null?d:v;}catch(e){return d;}};
  const _lsSet=(k,v)=>{try{window.localStorage.setItem(k,v);}catch(e){}};
  const _lsDel=(k)=>{try{window.localStorage.removeItem(k);}catch(e){}};
  const _initialToken=_lsGet("nxp_token","");
  const _initialRole=_lsGet("nxp_role","");
  const _initialAuthed=!!_initialToken;
  const[authed,setAuthed]=useState(_initialAuthed),[token,setToken]=useState(_initialToken),[role,setRole]=useState(_initialRole);
  const[email,setEmail]=useState(""),[pass,setPass]=useState(""),[loginErr,setLoginErr]=useState(""),[logging,setLogging]=useState(false);
'@

Write-Step "Patch 1: hydrate auth state from localStorage"
if ($content -notmatch [regex]::Escape($p1_old)) {
    Write-Fail "Patch 1 source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p1_old, $p1_new)
Write-Pass "Patch 1 applied"

# ----- PATCH 2: persist token to localStorage on login success -----
$p2_old = @'
      const d=await r.json();setToken(d.token);
      try{const p=JSON.parse(atob(d.token.split(".")[1]));setRole(p.role||"employee")}catch{setRole("employee")}
      setAuthed(true);setLoginErr("");
'@

$p2_new = @'
      const d=await r.json();setToken(d.token);_lsSet("nxp_token",d.token||"");
      try{const p=JSON.parse(atob(d.token.split(".")[1]));const _r=p.role||"employee";setRole(_r);_lsSet("nxp_role",_r);}catch{setRole("employee");_lsSet("nxp_role","employee");}
      setAuthed(true);setLoginErr("");
'@

Write-Step "Patch 2: persist token + role on login"
if ($content -notmatch [regex]::Escape($p2_old)) {
    Write-Fail "Patch 2 source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p2_old, $p2_new)
Write-Pass "Patch 2 applied"

# ----- PATCH 3: clear localStorage on Sign Out -----
$p3_old = 'React.createElement("button",{className:"btn-out",onClick:()=>{setAuthed(false);if(typeof showPublicView==='+"'"+'function'+"'"+')showPublicView()}},"Sign Out")'
$p3_new = 'React.createElement("button",{className:"btn-out",onClick:()=>{setAuthed(false);setToken("");setRole("");_lsDel("nxp_token");_lsDel("nxp_role");if(typeof showPublicView==='+"'"+'function'+"'"+')showPublicView()}},"Sign Out")'

Write-Step "Patch 3: clear localStorage on Sign Out"
if ($content -notmatch [regex]::Escape($p3_old)) {
    Write-Fail "Patch 3 source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p3_old, $p3_new)
Write-Pass "Patch 3 applied"

# ----- PATCH 4a: guard Save Quote against empty token -----
$p4a_old = @'
  const saveQuote=async()=>{
    setQStatus({type:"loading",msg:"Saving quote\u2026"});
'@

$p4a_new = @'
  const saveQuote=async()=>{
    if(!token){setQStatus({type:"err",msg:"Session expired. Please sign in again."});setAuthed(false);_lsDel("nxp_token");_lsDel("nxp_role");return;}
    setQStatus({type:"loading",msg:"Saving quote\u2026"});
'@

Write-Step "Patch 4a: guard Save Quote against empty token"
if ($content -notmatch [regex]::Escape($p4a_old)) {
    Write-Fail "Patch 4a source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p4a_old, $p4a_new)
Write-Pass "Patch 4a applied"

# ----- PATCH 4b: guard Generate AI Proposal against empty token -----
$p4b_old = @'
  const generateProposal=async()=>{
    if(!mName){setQStatus({type:"err",msg:"Enter a merchant name first."});return;}
'@

$p4b_new = @'
  const generateProposal=async()=>{
    if(!token){setQStatus({type:"err",msg:"Session expired. Please sign in again."});setAuthed(false);_lsDel("nxp_token");_lsDel("nxp_role");return;}
    if(!mName){setQStatus({type:"err",msg:"Enter a merchant name first."});return;}
'@

Write-Step "Patch 4b: guard Generate AI Proposal against empty token"
if ($content -notmatch [regex]::Escape($p4b_old)) {
    Write-Fail "Patch 4b source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p4b_old, $p4b_new)
Write-Pass "Patch 4b applied"

Write-Section "WRITING PATCHED FILE"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Resolve-Path $Target).Path, $content, $utf8NoBom)
Write-Pass "Wrote patched index.html"

Write-Section "POST-FLIGHT VERIFICATION"

$finalSize = (Get-Item $Target).Length
Write-Step "Final size: $finalSize bytes (expected ~$ExpectedFinalBytes)"
if ($finalSize -lt 101000 -or $finalSize -gt 102500) {
    Write-Fail "Final size $finalSize is outside expected range. Investigate."
    exit 3
}
Write-Pass "Final size in expected range"

$markers = @(
    @{ Pattern = '_lsGet';                    MinCount = 4 },
    @{ Pattern = '_lsSet."nxp_token"';        MinCount = 1 },
    @{ Pattern = '_lsDel."nxp_token"';        MinCount = 3 },
    @{ Pattern = 'Session expired';           MinCount = 2 },
    @{ Pattern = 'nxp_role';                  MinCount = 4 }
)

$allMarkersOk = $true
foreach ($m in $markers) {
    $count = ([regex]::Matches($content, $m.Pattern)).Count
    if ($count -ge $m.MinCount) {
        Write-Pass "Marker '$($m.Pattern)' found $count times (>= $($m.MinCount))"
    } else {
        Write-Fail "Marker '$($m.Pattern)' found $count times (need >= $($m.MinCount))"
        $allMarkersOk = $false
    }
}

Write-Section "RESULT"
if ($allMarkersOk) {
    Write-Host "  SUCCESS: All four patches applied and verified." -ForegroundColor Green
    Write-Host "  Next step: run 'git diff index.html' to review changes." -ForegroundColor Green
    exit 0
} else {
    Write-Host "  FAILURE: Patches applied but post-flight verification failed." -ForegroundColor Red
    Write-Host "  Restore from backup: Copy-Item .\index.html.backup-step8 .\index.html -Force" -ForegroundColor Red
    exit 4
}
