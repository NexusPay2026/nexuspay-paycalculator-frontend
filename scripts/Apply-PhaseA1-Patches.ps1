# =====================================================================
# Apply-PhaseA1-Patches.ps1  (v2 — CRLF-explicit)
# ---------------------------------------------------------------------
# Phase A1: Stop the bleeding (3 fixes)
#
#   Patch 1a: AI Proposal handler — store dict (not blank) in state
#   Patch 1b: AI Proposal render — delegate to renderProposal helper
#   Patch 1c: Inject renderProposal helper + ErrorBoundary class
#   Patch 3a: Customer pubPDF defensive guard at function entry
#   Patch 3b: Customer pubPDF try/catch at function exit
#
# IMPORTANT: All multi-line match strings use explicit `r`n for line endings,
# ensuring they match the file's actual CRLF line endings regardless of how
# this .ps1 file itself is encoded.
#
# SAFETY:
#   - Verifies baseline MD5 BEFORE any modification
#   - Aborts cleanly on any failure WITHOUT modifying the file
#   - Saves backup BEFORE writing
#   - Verifies markers exist after write
# =====================================================================

$ErrorActionPreference = "Stop"

$Target = ".\index.html"
$ExpectedBaselineMd5 = "6A0316831BDEE5C4D9F612E1A9661286"
$ExpectedBaselineBytes = 102831

function Write-Step($msg)    { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Pass($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail($msg)    { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Yellow }

# ---------------------------------------------------------------------
# PRE-FLIGHT
# ---------------------------------------------------------------------
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
    exit 1
}
Write-Pass "index.html is exactly $ExpectedBaselineBytes bytes (baseline match)"

$baselineMd5 = (Get-FileHash $Target -Algorithm MD5).Hash
if ($baselineMd5 -ne $ExpectedBaselineMd5) {
    Write-Fail "MD5 mismatch."
    Write-Fail "Got:      $baselineMd5"
    Write-Fail "Expected: $ExpectedBaselineMd5"
    exit 1
}
Write-Pass "MD5 hash matches baseline ($baselineMd5)"

# ---------------------------------------------------------------------
# BACKUP
# ---------------------------------------------------------------------
Write-Section "BACKUP"
$backupPath = ".\index.html.backup-phaseA1"
Copy-Item $Target $backupPath -Force
Write-Pass "Backup saved to $backupPath"

# ---------------------------------------------------------------------
# READ
# ---------------------------------------------------------------------
Write-Section "READING FILE"
$content = [System.IO.File]::ReadAllText((Resolve-Path $Target).Path, [System.Text.UTF8Encoding]::new($false))
Write-Pass "Read $($content.Length) characters"

# ---------------------------------------------------------------------
# PATCH 1a — AI Proposal handler stores dict
# ---------------------------------------------------------------------
# Match: the unique 3-line block in generateProposal that does the bad
# string-coercion and setProposal().
# Use explicit `r`n line joiners so this matches file's CRLF.

$p1a_old = '      const d=await r.json();' + "`r`n" + `
           '      const txt=d.analysis||d.proposal||d.recommendation||d.result||JSON.stringify(d,null,2);' + "`r`n" + `
           '      setProposal(txt);setQStatus({type:"ok",msg:"Proposal generated!"});'

$p1a_new = '      const d=await r.json();' + "`r`n" + `
           '      // Backend returns {analysis: {dict}, validation, residuals, ...}. Store the dict.' + "`r`n" + `
           '      let proposalData;' + "`r`n" + `
           '      if(d.analysis&&typeof d.analysis==="object"){proposalData=d.analysis;}' + "`r`n" + `
           '      else if(typeof d.analysis==="string"){proposalData=d.analysis;}' + "`r`n" + `
           '      else{proposalData=d.proposal||d.recommendation||d.result||JSON.stringify(d,null,2);}' + "`r`n" + `
           '      setProposal(proposalData);setQStatus({type:"ok",msg:"Proposal generated!"});'

Write-Section "APPLYING PATCHES"
Write-Step "Patch 1a: AI Proposal handler stores dict"
if ($content.IndexOf($p1a_old) -lt 0) {
    Write-Fail "Patch 1a source string not found. ABORTING. File NOT modified."
    exit 2
}
$matchCount1a = ([regex]::Matches($content, [regex]::Escape($p1a_old))).Count
if ($matchCount1a -gt 1) {
    Write-Fail "Patch 1a source string is AMBIGUOUS (matches $matchCount1a times). ABORTING."
    exit 2
}
$content = $content.Replace($p1a_old, $p1a_new)
Write-Pass "Patch 1a applied"

# ---------------------------------------------------------------------
# PATCH 1b — JSX render delegates to renderProposal()
# ---------------------------------------------------------------------

$p1b_old = '      qStatus&&React.createElement("div",{className:"act-status "+qStatus.type},qStatus.msg),' + "`r`n" + `
           '      proposal&&React.createElement("div",{className:"proposal-box"},proposal)),'

$p1b_new = '      qStatus&&React.createElement("div",{className:"act-status "+qStatus.type},qStatus.msg),' + "`r`n" + `
           '      proposal&&renderProposal(proposal,isAdmin)),'

Write-Step "Patch 1b: JSX render delegates"
if ($content.IndexOf($p1b_old) -lt 0) {
    Write-Fail "Patch 1b source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p1b_old, $p1b_new)
Write-Pass "Patch 1b applied"

# ---------------------------------------------------------------------
# PATCH 1c — Inject renderProposal + ErrorBoundary before ReactDOM.render
# ---------------------------------------------------------------------
# Build the new code as a single string with explicit CRLFs.

$p1c_old = 'function nb(l,v,s,c){return React.createElement("div",null,React.createElement("div",{className:"num-lbl"},l),React.createElement("div",{className:"num-val",style:{color:c}},v),s&&React.createElement("div",{className:"num-sub"},s))}' + "`r`n" + `
           'ReactDOM.render(React.createElement(App),document.getElementById("app"));'

# Build the injection text. Each line uses `r`n explicit.
$nl = "`r`n"
$inject = @(
    'function nb(l,v,s,c){return React.createElement("div",null,React.createElement("div",{className:"num-lbl"},l),React.createElement("div",{className:"num-val",style:{color:c}},v),s&&React.createElement("div",{className:"num-sub"},s))}',
    '',
    '// renderProposal: handles AI proposal data which may be a dict (from backend) or string (fallback).',
    'function renderProposal(p,isAdmin){',
    '  if(!p)return null;',
    '  if(typeof p==="string"){return React.createElement("div",{className:"proposal-box"},p);}',
    '  // Dict case: structured render. Backend keys: recommended_program, reasoning,',
    '  // deal_strength, competitive_position, negotiation_tips, risk_factors, merchant_pitch,',
    '  // internal_notes, optimal_markup_pct, annual_nexuspay_value, win_probability,',
    '  // multi_location_strategy, _provider, _providerCount, _confidence, _errors',
    '  const sec=(label,val,emphasize)=>{',
    '    if(val===undefined||val===null||val==="")return null;',
    '    const valStr=typeof val==="object"?JSON.stringify(val,null,2):String(val);',
    '    return React.createElement("div",{key:label,style:{marginBottom:12}},',
    '      React.createElement("div",{style:{fontSize:10,fontWeight:700,letterSpacing:".08em",color:"var(--teal)",fontFamily:"var(--mono)",marginBottom:4}},label.toUpperCase()),',
    '      React.createElement("div",{style:{fontSize:emphasize?14:12,fontWeight:emphasize?600:400,color:"var(--t1)",lineHeight:1.6,whiteSpace:"pre-wrap"}},valStr));',
    '  };',
    '  const children=[];',
    '  if(p._providerCount){',
    '    children.push(React.createElement("div",{key:"hdr",style:{fontSize:9,color:"var(--teal)",fontWeight:700,fontFamily:"var(--mono)",letterSpacing:".08em",marginBottom:10}},"AI CONSENSUS \u00B7 "+p._providerCount+" PROVIDER"+(p._providerCount>1?"S":"")+(p._confidence?" \u00B7 "+String(p._confidence).toUpperCase():"")));',
    '  }',
    '  children.push(sec("Recommended Program",p.recommended_program,true));',
    '  children.push(sec("Merchant Pitch",p.merchant_pitch));',
    '  children.push(sec("Reasoning",p.reasoning));',
    '  children.push(sec("Competitive Position",p.competitive_position));',
    '  if(p.optimal_markup_pct!==undefined&&p.optimal_markup_pct!==null)children.push(sec("Optimal Markup",p.optimal_markup_pct+"%"));',
    '  if(p.annual_nexuspay_value!==undefined&&p.annual_nexuspay_value!==null)children.push(sec("Annual NexusPay Value","$"+p.annual_nexuspay_value));',
    '  if(p.win_probability!==undefined&&p.win_probability!==null)children.push(sec("Win Probability",p.win_probability));',
    '  children.push(sec("Multi-Location Strategy",p.multi_location_strategy));',
    '  children.push(sec("Negotiation Tips",p.negotiation_tips));',
    '  children.push(sec("Deal Strength",p.deal_strength));',
    '  children.push(sec("Risk Factors",p.risk_factors));',
    '  if(isAdmin)children.push(sec("Internal Notes",p.internal_notes));',
    '  return React.createElement("div",{className:"proposal-box"},children.filter(Boolean));',
    '}',
    '',
    '// ErrorBoundary: catches render-time exceptions, shows recoverable message instead of blank page',
    'class ErrorBoundary extends React.Component{',
    '  constructor(props){super(props);this.state={hasError:false,errorMsg:""};}',
    '  static getDerivedStateFromError(err){return{hasError:true,errorMsg:String(err&&err.message||err||"Unknown error")};}',
    '  componentDidCatch(err,info){if(window.console&&console.error)console.error("ErrorBoundary caught:",err,info);}',
    '  render(){',
    '    if(this.state.hasError){',
    '      return React.createElement("div",{style:{padding:30,maxWidth:600,margin:"40px auto",fontFamily:"system-ui,sans-serif",color:"#0f1a2e"}},',
    '        React.createElement("h2",{style:{color:"#b91c1c",marginBottom:12}},"Something went wrong"),',
    '        React.createElement("p",{style:{marginBottom:16}},"The page encountered an unexpected error. Your session is preserved."),',
    '        React.createElement("p",{style:{fontFamily:"monospace",fontSize:12,background:"#f1f5f9",padding:10,borderRadius:4,marginBottom:16}},this.state.errorMsg),',
    '        React.createElement("button",{onClick:()=>{this.setState({hasError:false,errorMsg:""});},style:{padding:"8px 16px",background:"#1a6dd4",color:"#fff",border:"none",borderRadius:4,cursor:"pointer",marginRight:8}},"Try again"),',
    '        React.createElement("button",{onClick:()=>{window.location.reload();},style:{padding:"8px 16px",background:"#64748b",color:"#fff",border:"none",borderRadius:4,cursor:"pointer"}},"Reload page"));',
    '    }',
    '    return this.props.children;',
    '  }',
    '}',
    '',
    'ReactDOM.render(React.createElement(ErrorBoundary,null,React.createElement(App)),document.getElementById("app"));'
) -join $nl

$p1c_new = $inject

Write-Step "Patch 1c: Inject renderProposal + ErrorBoundary"
if ($content.IndexOf($p1c_old) -lt 0) {
    Write-Fail "Patch 1c source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p1c_old, $p1c_new)
Write-Pass "Patch 1c applied"

# ---------------------------------------------------------------------
# PATCH 3a — Customer PDF defensive guard at function entry
# ---------------------------------------------------------------------

$p3a_old = "function pubPDF(){var j=new(window.jspdf.jsPDF),"
$p3a_new = "function pubPDF(){try{if(!window.jspdf||!window.jspdf.jsPDF){pubToast('PDF library not loaded - please refresh the page');return;}var j=new(window.jspdf.jsPDF),"

Write-Step "Patch 3a: Customer PDF entry guard"
if ($content.IndexOf($p3a_old) -lt 0) {
    Write-Fail "Patch 3a source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p3a_old, $p3a_new)
Write-Pass "Patch 3a applied"

# ---------------------------------------------------------------------
# PATCH 3b — Customer PDF try/catch close at function exit
# ---------------------------------------------------------------------

$p3b_old = "j.save('NexusPay-Proposal-'+nm.replace(/[^a-zA-Z0-9]/g,'-')+'.pdf');pubToast('PDF saved')}"
$p3b_new = "j.save('NexusPay-Proposal-'+nm.replace(/[^a-zA-Z0-9]/g,'-')+'.pdf');pubToast('PDF saved')}catch(e){if(window.console&&console.error)console.error('pubPDF error:',e);pubToast('PDF generation failed - '+(e&&e.message?e.message:'unknown error'));}}"

Write-Step "Patch 3b: Customer PDF try/catch close"
if ($content.IndexOf($p3b_old) -lt 0) {
    Write-Fail "Patch 3b source string not found. ABORTING. File NOT modified."
    exit 2
}
$content = $content.Replace($p3b_old, $p3b_new)
Write-Pass "Patch 3b applied"

# ---------------------------------------------------------------------
# WRITE
# ---------------------------------------------------------------------
Write-Section "WRITING PATCHED FILE"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Resolve-Path $Target).Path, $content, $utf8NoBom)
Write-Pass "Wrote patched index.html"

# ---------------------------------------------------------------------
# POST-FLIGHT
# ---------------------------------------------------------------------
Write-Section "POST-FLIGHT VERIFICATION"

$finalSize = (Get-Item $Target).Length
Write-Step "Final size: $finalSize bytes (was $ExpectedBaselineBytes)"
if ($finalSize -lt 105000 -or $finalSize -gt 115000) {
    Write-Fail "Final size $finalSize is outside expected range (105000-115000)"
    exit 3
}
Write-Pass "Final size in expected range"

$markers = @(
    @{ Pattern = 'function renderProposal\(';                MinCount = 1; Label = 'renderProposal helper defined' },
    @{ Pattern = 'class ErrorBoundary extends React\.Component'; MinCount = 1; Label = 'ErrorBoundary class defined' },
    @{ Pattern = 'React\.createElement\(ErrorBoundary';      MinCount = 1; Label = 'ErrorBoundary wraps App' },
    @{ Pattern = 'renderProposal\(proposal,isAdmin\)';       MinCount = 1; Label = 'JSX delegates to renderProposal' },
    @{ Pattern = 'AI CONSENSUS';                             MinCount = 1; Label = 'AI consensus header text' },
    @{ Pattern = 'PDF library not loaded';                   MinCount = 1; Label = 'PDF guard message' },
    @{ Pattern = 'PDF generation failed';                    MinCount = 1; Label = 'PDF catch handler' },
    @{ Pattern = 'proposalData';                             MinCount = 4; Label = 'proposalData var (declared + 3 assignments)' }
)

$allOk = $true
foreach ($m in $markers) {
    $count = ([regex]::Matches($content, $m.Pattern)).Count
    if ($count -ge $m.MinCount) {
        Write-Pass "$($m.Label) found $count time(s) (>= $($m.MinCount))"
    } else {
        Write-Fail "$($m.Label) found $count time(s) (need >= $($m.MinCount))"
        $allOk = $false
    }
}

# Confirm earlier auth patches still intact
Write-Step "Confirming auth patches preserved..."
$authMarkers = @('_lsGet', 'nxp_token', 'Session expired')
$authOk = $true
foreach ($am in $authMarkers) {
    $c = ([regex]::Matches($content, $am)).Count
    if ($c -lt 1) {
        Write-Fail "Auth marker '$am' lost! ABORTING."
        $authOk = $false
        $allOk = $false
    }
}
if ($authOk) { Write-Pass "All auth patches preserved" }

Write-Section "RESULT"
if ($allOk) {
    Write-Host "  SUCCESS: Phase A1 patches applied and verified." -ForegroundColor Green
    Write-Host "  Backup at: $backupPath" -ForegroundColor Green
    Write-Host "  Next step: run 'git diff index.html' to review changes." -ForegroundColor Green
    exit 0
} else {
    Write-Host "  FAILURE: Patches written but post-flight verification failed." -ForegroundColor Red
    Write-Host "  Restore from backup: Copy-Item $backupPath .\index.html -Force" -ForegroundColor Red
    exit 4
}
