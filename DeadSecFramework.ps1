            param(
    [string]$Root = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Resolve-ProjectRoot {
    param([string]$Start)
    $cands = @(
        $Start,
        (Split-Path -Parent $Start),
        (Split-Path -Parent (Split-Path -Parent $Start))
    ) | Select-Object -Unique

    foreach($c in $cands){
        if(-not $c){ continue }
        if(Test-Path (Join-Path $c 'quiz-data')){
            return $c
        }
    }
    throw "Could not resolve project root from: $Start"
}

$ProjectRoot  = Resolve-ProjectRoot -Start $Root
$QuizDataDir  = Join-Path $ProjectRoot 'quiz-data'
$SectionsPath = Join-Path $QuizDataDir 'sections.json'
$VariablesPath= Join-Path $QuizDataDir 'variables.json'
$BiasPath     = Join-Path $QuizDataDir 'section-variable-bias.json'
$StoriesDir   = Join-Path $QuizDataDir 'stories'
$QuestionsDir = Join-Path $QuizDataDir 'questions'
$ManPagesDir  = Join-Path $QuizDataDir 'man-pages'
$NotesRootDir = Join-Path $QuizDataDir 'notes'
$NotesQuestionsDir = Join-Path $NotesRootDir 'questions'
$NotesStoriesDir = Join-Path $NotesRootDir 'stories'
function Read-Json([string]$Path){
    return (Get-Content $Path -Raw | ConvertFrom-Json)
}

function Resolve-QuestionFile([string]$relPath){
    $norm = [string]$relPath
    if([string]::IsNullOrWhiteSpace($norm)){ return $null }
    $norm = $norm.Replace('\','/')
    if($norm.StartsWith('questions/', [System.StringComparison]::OrdinalIgnoreCase)){
        $norm = $norm.Substring(10)
    }
    $external = Join-Path $QuestionsDir ($norm.Replace('/','\'))
    if(Test-Path $external){ return $external }
    $embeddedStyle = Join-Path $QuizDataDir ([string]$relPath)
    if(Test-Path $embeddedStyle){ return $embeddedStyle }
    $legacy = Join-Path $QuizDataDir (Join-Path 'questions' $norm)
    if(Test-Path $legacy){ return $legacy }
    return $null
}

$Sections = Read-Json $SectionsPath
$Variables = Read-Json $VariablesPath
$SectionBias = @{}
if(Test-Path $BiasPath){
    $sb = Read-Json $BiasPath
    foreach($p in $sb.PSObject.Properties){ $SectionBias[$p.Name] = $p.Value }
}

$TokenMap = [ordered]@{
    '<IP>'='ips'; '<user>'='users'; '<pass>'='passwords'; '<domain>'='domains'; '<hash>'='hashes'; '<payload>'='payloads'; '<exfil>'='exfil'; '<pid>'='pids'; '<hostname>'='hostnames'; '<port>'='ports'; '<email>'='emails'; '<service>'='services'; '<file_path>'='file_paths'; '<txt>'='txt_files'; '<command>'='commands'; '<dirw>'='dir_wordlists'; '<sleep>'='sleep'; '<jitter>'='jitter'; '<listener>'='listener'; '<pipe>'='pipes'; '<service_name>'='service_name'; '<servicename>'='service_name'; '<linux_user>'='linux_users'; '<mount>'='mount_points'; '<cron_path>'='cron_paths'; '<suid_bin>'='suid_bins'; '<namespace>'='kube_namespaces'; '<pod>'='pods'; '<image>'='container_images'; '<realm>'='realms'; '<ticket>'='tickets'; '<fhost>'='fantasy_hosts'; '<rune>'='runes'; '<glyph>'='glyphs'; '<artifact>'='artifacts'; '<fport>'='fantasy_ports'; '<cidr>'='subnets'; '<subnet>'='subnets'; '<subnets>'='subnets'; '<url>'='urls'
}

function Get-PropValue($obj,[string]$name){
    if($null -eq $obj){ return $null }
    $p = $obj.PSObject.Properties[$name]
    if($p){ return $p.Value }
    return $null
}

function Get-OptionalProp($obj,[string]$name){
    if($null -eq $obj){ return $null }
    $p = $obj.PSObject.Properties[$name]
    if($p){ return $p.Value }
    return $null
}

function Get-ValueForToken([string]$sectionId,[string]$poolName){
    $pool = $null
    if($SectionBias.ContainsKey($sectionId)){ $pool = Get-PropValue $SectionBias[$sectionId] $poolName }
    if($null -eq $pool){ $pool = Get-PropValue $Variables $poolName }
    $arr = @($pool)
    if($arr.Count -eq 0){ return $null }
    return (Get-Random -InputObject $arr)
}

function Replace-First([string[]]$lines,[string]$token,[string]$value){
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach($line in $lines){
        if(-not $done -and $line.Contains($token)){
            $idx = $line.IndexOf($token)
            $out.Add($line.Substring(0,$idx) + $value + $line.Substring($idx + $token.Length))
            $done = $true
        } else {
            $out.Add($line)
        }
    }
    return ,$out.ToArray()
}

function Instantiate-Question($q,[string]$sectionId){
    $question = @($q.question | ForEach-Object { [string]$_ })
    $answer = [string]$q.answer
    $alts = @()
    if($q.PSObject.Properties['alternate_answers'] -and $q.alternate_answers){
        $alts = @($q.alternate_answers | ForEach-Object { [string]$_ })
    }

    foreach($kv in $TokenMap.GetEnumerator()){
        $token = [string]$kv.Key
        $pool  = [string]$kv.Value
        $has = (($question -join "`n").Contains($token)) -or $answer.Contains($token) -or (($alts -join "`n").Contains($token))
        if(-not $has){ continue }

        $valObj = Get-ValueForToken -sectionId $sectionId -poolName $pool
        if($null -eq $valObj){ continue }
        $val = [string]$valObj

        $question = Replace-First -lines $question -token $token -value $val
        $answer = $answer.Replace($token,$val)
        for($i=0; $i -lt $alts.Count; $i++){ $alts[$i] = $alts[$i].Replace($token,$val) }

        if($token -eq '<sleep>'){
            $secs = ([int]$val * 60).ToString()
            $answer = $answer.Replace('<sleep_seconds>',$secs)
            for($i=0; $i -lt $alts.Count; $i++){ $alts[$i] = $alts[$i].Replace('<sleep_seconds>',$secs) }
        }
    }

    return [pscustomobject]@{
        question = $question
        answer = $answer
        alternate_answers = $alts
        section_id = $sectionId
    }
}

function Normalize-Command([string]$s){
    if([string]::IsNullOrWhiteSpace($s)){ return '' }
    $n = [regex]::Replace($s.Trim(), '\s+', ' ')
    $n = [regex]::Replace($n, '(?<=^|\s)-p\s+([^\s]+)', '-p$1')
    $n = [regex]::Replace($n, '(?<=^|\s)-T\s+([^\s]+)', '-T$1')
    $n = [regex]::Replace($n, '(?<=^|\s)--script\s+([^\s]+)', '--script=$1')
    $n = [regex]::Replace($n, '(?<=^|\s)--([A-Za-z0-9_-]+)\s*=\s*([^\s]+)', '--$1=$2')
    return $n
}

function Tokenize-Command([string]$s){
    $list = New-Object System.Collections.Generic.List[string]
    $m = [regex]::Matches($s, '"(?:\\.|[^"])*"|''(?:\\.|[^''])*''|\S+')
    foreach($x in $m){ if($x.Success){ $list.Add($x.Value) } }
    return ,$list.ToArray()
}

function Equivalent-ByTokenBag([string]$a,[string]$b){
    $ta = Tokenize-Command $a
    $tb = Tokenize-Command $b
    if($ta.Count -eq 0 -or $tb.Count -eq 0){ return $false }
    if($ta[0] -cne $tb[0]){ return $false }
    if($ta.Count -ne $tb.Count){ return $false }

    $bag = @{}
    for($i=1; $i -lt $ta.Count; $i++){
        if(-not $bag.ContainsKey($ta[$i])){ $bag[$ta[$i]] = 0 }
        $bag[$ta[$i]]++
    }
    for($i=1; $i -lt $tb.Count; $i++){
        if(-not $bag.ContainsKey($tb[$i])){ return $false }
        $bag[$tb[$i]]--
        if($bag[$tb[$i]] -eq 0){ $bag.Remove($tb[$i]) }
    }
    return ($bag.Count -eq 0)
}

function Test-Answer([string]$user,[string]$expected,[string[]]$alts){
    $u = [regex]::Replace($user.Trim(), '^\>\:?\s*', '')
    $nu = Normalize-Command $u
    $all = @($expected) + @($alts)
    foreach($a in $all){
        if([string]::IsNullOrWhiteSpace($a)){ continue }
        $t = $a.Trim()
        $nt = Normalize-Command $t
        if($u -ceq $t){ return $true }
        if($nu -ceq $nt){ return $true }
        if(Equivalent-ByTokenBag $nu $nt){ return $true }
    }
    return $false
}

$script:Stories = @()
$script:ManPages = @{}
$script:ManForm = $null
$script:ManList = $null
$script:ManViewer = $null
$script:ManBack = $null
$script:ManTitle = $null
$script:NotesForm = $null
$script:NotesEditor = $null
$script:NotesPathLabel = $null
$script:NotesPath = ''
$script:Items = @()
$script:Index = 0
$script:Score = 0
$script:Started = $false
$script:IsStory = $false
$script:CurrentTitle = ''
$script:Beacons = New-Object System.Collections.ArrayList

function Reset-State {
    $script:Items = @()
    $script:Index = 0
    $script:Score = 0
    $script:Started = $false
    $script:IsStory = $false
    $script:CurrentTitle = ''
    $script:Beacons.Clear()
}

function Get-SafeFileName([string]$name){
    if([string]::IsNullOrWhiteSpace($name)){ return 'story-notes' }
    $safe = $name
    foreach($c in [System.IO.Path]::GetInvalidFileNameChars()){
        $safe = $safe.Replace([string]$c,'-')
    }
    $safe = [regex]::Replace($safe,'\s+',' ')
    $safe = $safe.Trim().Trim('.')
    if([string]::IsNullOrWhiteSpace($safe)){ return 'story-notes' }
    return $safe
}

function Ensure-NotesFolders {
    if(-not (Test-Path $NotesQuestionsDir)){ [void](New-Item -ItemType Directory -Path $NotesQuestionsDir -Force) }
    if(-not (Test-Path $NotesStoriesDir)){ [void](New-Item -ItemType Directory -Path $NotesStoriesDir -Force) }
}

function Get-ActiveNotesPath {
    if(-not $script:Started){ return $null }
    Ensure-NotesFolders
    if($script:IsStory){
        $name = $script:CurrentTitle
        if([string]::IsNullOrWhiteSpace($name) -and $cmbStories.SelectedIndex -ge 0){
            $name = [string]$cmbStories.SelectedItem
        }
        $file = (Get-SafeFileName $name) + '.txt'
        return (Join-Path $NotesStoriesDir $file)
    }
    return (Join-Path $NotesQuestionsDir 'questions-notes.txt')
}

function Ensure-NotesForm {
    if($script:NotesForm -and -not $script:NotesForm.IsDisposed){ return $script:NotesForm }

    $nf = New-Object System.Windows.Forms.Form
    $nf.Text = 'DeadSec Framework - Notes'
    $nf.StartPosition = 'CenterParent'
    $nf.Size = New-Object System.Drawing.Size(900,640)
    $nf.MinimumSize = New-Object System.Drawing.Size(600,420)
    $nf.BackColor = $bg
    $nf.ForeColor = $fg

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(10,10)
    $lbl.Size = New-Object System.Drawing.Size(860,22)
    $lbl.ForeColor = $fg
    $lbl.Text = ''
    $lbl.Anchor = 'Top,Left,Right'
    $nf.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(10,38)
    $txt.Size = New-Object System.Drawing.Size(860,520)
    $txt.Multiline = $true
    $txt.ScrollBars = 'Both'
    $txt.AcceptsReturn = $true
    $txt.AcceptsTab = $true
    $txt.WordWrap = $false
    $txt.Font = New-Object System.Drawing.Font('Consolas',11,[System.Drawing.FontStyle]::Regular)
    $txt.BackColor = [System.Drawing.Color]::Black
    $txt.ForeColor = $fg
    $txt.Anchor = 'Top,Bottom,Left,Right'
    $nf.Controls.Add($txt)

    $btnSaveNotes = New-Object System.Windows.Forms.Button
    $btnSaveNotes.Text = 'Save'
    $btnSaveNotes.Location = New-Object System.Drawing.Point(10,566)
    $btnSaveNotes.Size = New-Object System.Drawing.Size(100,34)
    $btnSaveNotes.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
    $btnSaveNotes.ForeColor = $fg
    $btnSaveNotes.Anchor = 'Bottom,Left'
    $nf.Controls.Add($btnSaveNotes)

    $btnCloseNotes = New-Object System.Windows.Forms.Button
    $btnCloseNotes.Text = 'Close'
    $btnCloseNotes.Location = New-Object System.Drawing.Point(120,566)
    $btnCloseNotes.Size = New-Object System.Drawing.Size(100,34)
    $btnCloseNotes.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
    $btnCloseNotes.ForeColor = $fg
    $btnCloseNotes.Anchor = 'Bottom,Left'
    $nf.Controls.Add($btnCloseNotes)

    $btnSaveNotes.Add_Click({
        if([string]::IsNullOrWhiteSpace($script:NotesPath)){ return }
        if($null -eq $script:NotesEditor){ return }
        [System.IO.File]::WriteAllText($script:NotesPath, [string]$script:NotesEditor.Text, [System.Text.Encoding]::UTF8)
    })

    $btnCloseNotes.Add_Click({
        if($script:NotesForm -and -not $script:NotesForm.IsDisposed){
            $script:NotesForm.Hide()
        }
    })

    $nf.Add_FormClosing({
        if($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing){
            $_.Cancel = $true
            if($script:NotesForm -and -not $script:NotesForm.IsDisposed){
                $script:NotesForm.Hide()
            }
        }
    })

    $script:NotesForm = $nf
    $script:NotesEditor = $txt
    $script:NotesPathLabel = $lbl
    return $script:NotesForm
}

function Open-NotesForActiveSession {
    $path = Get-ActiveNotesPath
    if([string]::IsNullOrWhiteSpace([string]$path)){ return }

    if(-not (Test-Path $path)){
        [System.IO.File]::WriteAllText($path,'',[System.Text.Encoding]::UTF8)
    }

    $nf = Ensure-NotesForm
    $script:NotesPath = $path
    $script:NotesPathLabel.Text = "File: $path"
    $script:NotesEditor.Text = [System.IO.File]::ReadAllText($path)
    if(-not $nf.Visible){ $nf.Show($form) }
    $nf.BringToFront()
    $script:NotesEditor.Focus()
}
function Load-ManPages {
    $script:ManPages = @{}
    $dir = $ManPagesDir
    if(-not (Test-Path $dir)){ $dir = Join-Path $QuizDataDir 'man-pages' }
    if(-not (Test-Path $dir)){ return }
    foreach($f in (Get-ChildItem $dir -File -Filter '*.txt' | Sort-Object Name)){
        if($f.Name -ieq 'fetch-report.txt'){ continue }
        $tool = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLowerInvariant()
        try {
            $script:ManPages[$tool] = Get-Content $f.FullName -Raw
        } catch {
            $script:ManPages[$tool] = \"Failed to read man page: $($f.Name)`r`n$($_.Exception.Message)\"
        }
    }
}

$bg = [System.Drawing.Color]::FromArgb(10,10,10)
$fg = [System.Drawing.Color]::Lime

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DeadSec Framework (PowerShell GUI)'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1450,920)
$form.MinimumSize = New-Object System.Drawing.Size(1200,760)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$form.ForeColor = [System.Drawing.Color]::White

$left = New-Object System.Windows.Forms.Panel
$left.Dock = 'Left'
$left.Width = 340
$left.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)

$main = New-Object System.Windows.Forms.Panel
$main.Dock = 'Fill'
$main.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)
$form.Controls.Add($main)
$form.Controls.Add($left)

$lblSections = New-Object System.Windows.Forms.Label
$lblSections.Text = 'Sections'
$lblSections.ForeColor = $fg
$lblSections.Location = New-Object System.Drawing.Point(10,10)
$lblSections.AutoSize = $true
$left.Controls.Add($lblSections)

$clbSections = New-Object System.Windows.Forms.CheckedListBox
$clbSections.Location = New-Object System.Drawing.Point(10,35)
$clbSections.Size = New-Object System.Drawing.Size(318,420)
$clbSections.BackColor = $bg
$clbSections.ForeColor = $fg
$left.Controls.Add($clbSections)
$null = $clbSections.Items.Add('0 - All (except 99)')
foreach($s in $Sections){ $null = $clbSections.Items.Add("$($s.id) - $($s.name)") }
$clbSections.SetItemChecked(0,$true)
$script:SectionCheckSync = $false
$script:SectionPendingIdx = -1
$script:SectionPendingState = [System.Windows.Forms.CheckState]::Unchecked
$clbSections.Add_ItemCheck({
    if($script:SectionCheckSync){ return }
    $script:SectionPendingIdx = [int]$_.Index
    $script:SectionPendingState = [System.Windows.Forms.CheckState]$_.NewValue
    $script:SectionCheckSync = $true
    [void]$form.BeginInvoke([Action]{
        try {
            $idx = $script:SectionPendingIdx
            $newState = $script:SectionPendingState
            if($idx -eq 0 -and $newState -eq [System.Windows.Forms.CheckState]::Checked){
                for($j=1; $j -lt $clbSections.Items.Count; $j++){ $clbSections.SetItemChecked($j,$false) }
                $clbSections.SetItemChecked(0,$true)
            } elseif($idx -gt 0 -and $newState -eq [System.Windows.Forms.CheckState]::Checked){
                if($clbSections.GetItemChecked(0)){ $clbSections.SetItemChecked(0,$false) }
            } elseif($idx -gt 0){
                $any = $false
                for($j=1; $j -lt $clbSections.Items.Count; $j++){ if($clbSections.GetItemChecked($j)){ $any = $true; break } }
                if(-not $any){ $clbSections.SetItemChecked(0,$true) }
            } elseif($idx -eq 0 -and $newState -ne [System.Windows.Forms.CheckState]::Checked){
                $any = $false
                for($j=1; $j -lt $clbSections.Items.Count; $j++){ if($clbSections.GetItemChecked($j)){ $any = $true; break } }
                if(-not $any){ $clbSections.SetItemChecked(0,$true) }
            }
        } finally {
            $script:SectionPendingIdx = -1
            $script:SectionPendingState = [System.Windows.Forms.CheckState]::Unchecked
            $script:SectionCheckSync = $false
        }
    })
})

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text = 'Question Count'
$lblCount.ForeColor = $fg
$lblCount.Location = New-Object System.Drawing.Point(10,470)
$lblCount.AutoSize = $true
$left.Controls.Add($lblCount)

$numCount = New-Object System.Windows.Forms.NumericUpDown
$numCount.Location = New-Object System.Drawing.Point(10,495)
$numCount.Size = New-Object System.Drawing.Size(120,34)
$numCount.Minimum = 1
$numCount.Maximum = 200
$numCount.Value = 10
$numCount.BackColor = $bg
$numCount.ForeColor = $fg
$left.Controls.Add($numCount)

$chkStory = New-Object System.Windows.Forms.CheckBox
$chkStory.Text = 'Story Mode'
$chkStory.ForeColor = $fg
$chkStory.Location = New-Object System.Drawing.Point(10,540)
$chkStory.AutoSize = $true
$left.Controls.Add($chkStory)

$cmbStories = New-Object System.Windows.Forms.ComboBox
$cmbStories.Location = New-Object System.Drawing.Point(10,568)
$cmbStories.Size = New-Object System.Drawing.Size(240,30)
$cmbStories.DropDownStyle = 'DropDownList'
$cmbStories.Enabled = $false
$cmbStories.BackColor = $bg
$cmbStories.ForeColor = $fg
$left.Controls.Add($cmbStories)

$btnReloadStories = New-Object System.Windows.Forms.Button
$btnReloadStories.Text = 'Reload'
$btnReloadStories.Location = New-Object System.Drawing.Point(258,566)
$btnReloadStories.Size = New-Object System.Drawing.Size(70,32)
$btnReloadStories.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$btnReloadStories.ForeColor = $fg
$btnReloadStories.Enabled = $false
$left.Controls.Add($btnReloadStories)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Quiz'
$btnStart.Location = New-Object System.Drawing.Point(10,610)
$btnStart.Size = New-Object System.Drawing.Size(212,40)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$btnStart.ForeColor = $fg
$left.Controls.Add($btnStart)

$btnNotes = New-Object System.Windows.Forms.Button
$btnNotes.Text = 'Notes'
$btnNotes.Location = New-Object System.Drawing.Point(10,656)
$btnNotes.Size = New-Object System.Drawing.Size(212,36)
$btnNotes.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$btnNotes.ForeColor = $fg
$left.Controls.Add($btnNotes)

$btnMan = New-Object System.Windows.Forms.Button
$btnMan.Text = 'Man Pages'
$btnMan.Location = New-Object System.Drawing.Point(228,610)
$btnMan.Size = New-Object System.Drawing.Size(100,40)
$btnMan.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$btnMan.ForeColor = $fg
$left.Controls.Add($btnMan)

$terminal = New-Object System.Windows.Forms.RichTextBox
$terminal.Location = New-Object System.Drawing.Point(10,10)
$terminal.Size = New-Object System.Drawing.Size(1070,650)
$terminal.BackColor = $bg
$terminal.ForeColor = $fg
$terminal.ReadOnly = $true
$terminal.BorderStyle = 'FixedSingle'
$terminal.Multiline = $true
$terminal.WordWrap = $true
$terminal.ScrollBars = 'Vertical'
$terminal.Font = New-Object System.Drawing.Font('Consolas',16,[System.Drawing.FontStyle]::Regular)
$terminal.Anchor = 'Top,Bottom,Left,Right'
$main.Controls.Add($terminal)

$beaconGroup = New-Object System.Windows.Forms.GroupBox
$beaconGroup.Text = 'Story Beacons'
$beaconGroup.ForeColor = $fg
$beaconGroup.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)
$beaconGroup.Location = New-Object System.Drawing.Point(10,665)
$beaconGroup.Size = New-Object System.Drawing.Size(1070,160)
$beaconGroup.Anchor = 'Left,Right,Bottom'
$beaconGroup.Visible = $false
$main.Controls.Add($beaconGroup)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.BackgroundColor = $bg
$grid.ForeColor = $fg
$grid.BorderStyle = 'FixedSingle'
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $fg
$grid.DefaultCellStyle.BackColor = $bg
$grid.DefaultCellStyle.ForeColor = $fg
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.RowHeadersVisible = $false
$null = $grid.Columns.Add('id','ID'); $grid.Columns['id'].Visible = $false
$null = $grid.Columns.Add('ip','IP')
$null = $grid.Columns.Add('hostname','Hostname')
$null = $grid.Columns.Add('username','Username')
$null = $grid.Columns.Add('mac','MAC Address')
$grid.Columns['ip'].Width = 150
$grid.Columns['hostname'].Width = 220
$grid.Columns['username'].Width = 220
$grid.Columns['mac'].AutoSizeMode = 'Fill'
$beaconGroup.Controls.Add($grid)

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(10,835)
$txtInput.Size = New-Object System.Drawing.Size(930,36)
$txtInput.BackColor = $bg
$txtInput.ForeColor = $fg
$txtInput.Font = New-Object System.Drawing.Font('Consolas',14)
$txtInput.Anchor = 'Left,Right,Bottom'
$main.Controls.Add($txtInput)

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = 'Send'
$btnSend.Location = New-Object System.Drawing.Point(950,833)
$btnSend.Size = New-Object System.Drawing.Size(130,40)
$btnSend.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
$btnSend.ForeColor = $fg
$btnSend.Anchor = 'Right,Bottom'
$main.Controls.Add($btnSend)

function Write-Terminal([string[]]$lines,[bool]$clear=$false){
    if($clear){ $terminal.Clear() }
    foreach($line in $lines){ $terminal.AppendText($line + [Environment]::NewLine) }
    $terminal.SelectionStart = $terminal.TextLength
    $terminal.ScrollToCaret()
}

function Update-BeaconGrid {
    $grid.Rows.Clear()
    foreach($b in $script:Beacons){
        $idx = $grid.Rows.Add()
        $grid.Rows[$idx].Cells['id'].Value = [string]$b.id
        $grid.Rows[$idx].Cells['ip'].Value = [string]$b.ip
        $grid.Rows[$idx].Cells['hostname'].Value = [string]$b.hostname
        $grid.Rows[$idx].Cells['username'].Value = [string]$b.username
        $grid.Rows[$idx].Cells['mac'].Value = [string]$b.mac_address
    }
}

function Upsert-Beacon($b){
    $id = [string]$b.id
    for($i=0; $i -lt $script:Beacons.Count; $i++){
        if([string]$script:Beacons[$i].id -ceq $id){
            $script:Beacons[$i] = $b
            return
        }
    }
    [void]$script:Beacons.Add($b)
}

function Remove-Beacon([string]$id){
    for($i=$script:Beacons.Count-1; $i -ge 0; $i--){
        if([string]$script:Beacons[$i].id -ceq $id){ $script:Beacons.RemoveAt($i) }
    }
}

function Apply-Outcome($outcome,[System.Collections.Generic.List[string]]$extra){
    if($null -eq $outcome){ return }
    $msgs = Get-OptionalProp $outcome 'messages'
    $brem = Get-OptionalProp $outcome 'beacon_remove'
    $badd = Get-OptionalProp $outcome 'beacon_add'
    $bupd = Get-OptionalProp $outcome 'beacon_update'
    if($msgs){ foreach($m in @($msgs)){ $extra.Add([string]$m) } }
    if($brem){ foreach($id in @($brem)){ Remove-Beacon ([string]$id) } }
    if($badd){ foreach($b in @($badd)){ Upsert-Beacon $b } }
    if($bupd){ foreach($b in @($bupd)){ Upsert-Beacon $b } }
    Update-BeaconGrid
}

function Show-CurrentQuestion([string[]]$feedback){
    if(-not $script:Started){ return }

    if($script:Index -ge $script:Items.Count){
        $total = [Math]::Max(1,$script:Items.Count)
        $pct = [math]::Round(($script:Score*100.0)/$total,1)
        $wrong = $total - $script:Score
        $lines = New-Object System.Collections.Generic.List[string]
        if($feedback){ foreach($f in $feedback){ $lines.Add($f) } }
        if($lines.Count -gt 0){ $lines.Add('') }
        $lines.Add('QUIZ COMPLETE')
        $lines.Add(('{0}%' -f $pct))
        $lines.Add(('{0}/{1}' -f $script:Score,$total))
        $lines.Add(('Correct: {0}    Wrong: {1}' -f $script:Score,$wrong))
        Write-Terminal -lines $lines.ToArray() -clear $true
        $script:Started = $false
        return
    }

    $cur = $script:Items[$script:Index]
    $lines = New-Object System.Collections.Generic.List[string]
    if($feedback){ foreach($f in $feedback){ $lines.Add($f) } $lines.Add('') }
    $lines.Add(('Question {0}/{1}:' -f ($script:Index+1),$script:Items.Count))
    $showPrev = Get-OptionalProp $cur 'show_previous_question'
    if($showPrev -and $script:Index -gt 0){
        $prev = $script:Items[$script:Index-1]
        foreach($line in @($prev.question)){ $lines.Add([string]$line) }
        $lines.Add('')
    }
    foreach($line in @($cur.question)){ $lines.Add([string]$line) }
    Write-Terminal -lines $lines.ToArray() -clear $true
}

function Reload-Stories {
    $script:Stories = @()
    $cmbStories.Items.Clear()
    if(-not (Test-Path $StoriesDir)){ return }

    foreach($f in (Get-ChildItem $StoriesDir -Filter '*.json' | Sort-Object Name)){
        try {
            $j = Read-Json $f.FullName
            $name = [string]$j.name
            if([string]::IsNullOrWhiteSpace($name)){ $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            $obj = [pscustomobject]@{ Name=$name; Path=$f.FullName; Story=$j }
            $script:Stories += $obj
            [void]$cmbStories.Items.Add($name)
        } catch {}
    }
    if($cmbStories.Items.Count -gt 0){ $cmbStories.SelectedIndex = 0 }
}

function Ensure-ManForm {
    if($script:ManForm -and -not $script:ManForm.IsDisposed){ return $script:ManForm }

    $script:ManForm = New-Object System.Windows.Forms.Form
    $script:ManForm.Text = 'DeadSec Framework - Man Pages'
    $script:ManForm.StartPosition = 'Manual'
    $script:ManForm.Size = New-Object System.Drawing.Size(980,860)
    $script:ManForm.MinimumSize = New-Object System.Drawing.Size(760,520)
    $script:ManForm.BackColor = $bg
    $script:ManForm.ForeColor = $fg

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = 42
    $top.BackColor = $bg
    $script:ManForm.Controls.Add($top)

    $script:ManBack = New-Object System.Windows.Forms.Button
    $script:ManBack.Text = '< Back to Tools'
    $script:ManBack.Location = New-Object System.Drawing.Point(8,8)
    $script:ManBack.Size = New-Object System.Drawing.Size(150,28)
    $script:ManBack.FlatStyle = 'Flat'
    $script:ManBack.FlatAppearance.BorderColor = [System.Drawing.Color]::Silver
    $script:ManBack.BackColor = [System.Drawing.Color]::FromArgb(20,20,20)
    $script:ManBack.ForeColor = $fg
    $script:ManBack.Visible = $false
    $top.Controls.Add($script:ManBack)

    $script:ManTitle = New-Object System.Windows.Forms.Label
    $script:ManTitle.AutoSize = $false
    $script:ManTitle.Location = New-Object System.Drawing.Point(170,11)
    $script:ManTitle.Size = New-Object System.Drawing.Size(760,24)
    $script:ManTitle.ForeColor = $fg
    $script:ManTitle.TextAlign = 'MiddleLeft'
    $script:ManTitle.Text = 'Tool Man Pages'
    $top.Controls.Add($script:ManTitle)

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = 'Fill'
    $content.BackColor = $bg
    $script:ManForm.Controls.Add($content)

    $script:ManList = New-Object System.Windows.Forms.ListBox
    $script:ManList.Dock = 'Fill'
    $script:ManList.BackColor = $bg
    $script:ManList.ForeColor = $fg
    $script:ManList.BorderStyle = 'FixedSingle'
    $script:ManList.Font = New-Object System.Drawing.Font('Consolas',12,[System.Drawing.FontStyle]::Regular)
    $content.Controls.Add($script:ManList)

    $script:ManViewer = New-Object System.Windows.Forms.RichTextBox
    $script:ManViewer.Dock = 'Fill'
    $script:ManViewer.BackColor = $bg
    $script:ManViewer.ForeColor = $fg
    $script:ManViewer.ReadOnly = $true
    $script:ManViewer.BorderStyle = 'FixedSingle'
    $script:ManViewer.WordWrap = $true
    $script:ManViewer.ScrollBars = 'Vertical'
    $script:ManViewer.Font = New-Object System.Drawing.Font('Consolas',12,[System.Drawing.FontStyle]::Regular)
    $script:ManViewer.Visible = $false
    $content.Controls.Add($script:ManViewer)
    $script:ManViewer.BringToFront()

    foreach($tool in @($script:ManPages.Keys | Sort-Object)){ [void]$script:ManList.Items.Add($tool) }

    $script:ManBack.Add_Click({
        if($null -eq $script:ManList -or $null -eq $script:ManViewer){ return }
        $script:ManViewer.Visible = $false
        $script:ManList.Visible = $true
        $script:ManBack.Visible = $false
        $script:ManTitle.Text = 'Tool Man Pages'
        $script:ManList.Focus()
    })

    $openTool = {
        if($null -eq $script:ManList -or $script:ManList.SelectedIndex -lt 0){ return }
        $tool = [string]$script:ManList.SelectedItem
        if($script:ManPages.ContainsKey($tool)){
            $script:ManViewer.Text = [string]$script:ManPages[$tool]
        } else {
            $script:ManViewer.Text = "No man page text found for: $tool"
        }
        $script:ManTitle.Text = "TOOL: $tool"
        $script:ManList.Visible = $false
        $script:ManViewer.Visible = $true
        $script:ManBack.Visible = $true
        $script:ManViewer.SelectionStart = 0
        $script:ManViewer.ScrollToCaret()
        $script:ManViewer.Focus()
    }

    $script:ManList.Add_DoubleClick($openTool)
    $script:ManList.Add_SelectedIndexChanged($openTool)

    $script:ManForm.Add_FormClosing({
        if($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing){
            $_.Cancel = $true
            if($script:ManForm -and -not $script:ManForm.IsDisposed){ $script:ManForm.Hide() }
        }
    })

    return $script:ManForm
}

$chkStory.Add_CheckedChanged({
    $enabled = $chkStory.Checked
    $cmbStories.Enabled = $enabled
    $btnReloadStories.Enabled = $enabled
    $beaconGroup.Visible = $enabled
})

$btnReloadStories.Add_Click({ Reload-Stories })
$btnNotes.Add_Click({ Open-NotesForActiveSession })
$btnMan.Add_Click({
    Load-ManPages
    $mf = Ensure-ManForm
    if($mf.Visible){
        $mf.Hide()
    } else {
        $mf.Location = New-Object System.Drawing.Point(($form.Left + $form.Width + 8), $form.Top)
        $mf.Show()
        $mf.BringToFront()
    }
})

$btnStart.Add_Click({
    Reset-State
    Update-BeaconGrid

    if($chkStory.Checked){
        if($cmbStories.SelectedIndex -lt 0){ [System.Windows.Forms.MessageBox]::Show('No story selected.'); return }
        $storyObj = $script:Stories[$cmbStories.SelectedIndex]
        $script:IsStory = $true
        $script:CurrentTitle = [string]$storyObj.Name
        $script:Items = @($storyObj.Story.steps)
        if($script:Items.Count -eq 0){ [System.Windows.Forms.MessageBox]::Show('Story has no steps.'); return }
        $script:Started = $true
        $intro = @("--- Story Mode: $($script:CurrentTitle) ---")
        if($storyObj.Story.description){ $intro += [string]$storyObj.Story.description }
        Show-CurrentQuestion -feedback $intro
        $txtInput.Focus()
        return
    }

    $selectedIds = @()
    foreach($item in $clbSections.CheckedItems){
        $entry = [string]$item
        $id = $entry.Split(' - ')[0].Trim()
        if($id -eq '0'){
            $selectedIds = @($Sections | Where-Object { [string]$_.id -ne '99' } | ForEach-Object { [string]$_.id })
            break
        }
        $selectedIds += $id
    }

    if($selectedIds.Count -eq 0){ [System.Windows.Forms.MessageBox]::Show('Select at least one section.'); return }

    $pool = New-Object System.Collections.ArrayList
    foreach($sid in $selectedIds){
        $sec = $Sections | Where-Object { [string]$_.id -eq $sid } | Select-Object -First 1
        if(-not $sec){ continue }
        $qfile = Resolve-QuestionFile -relPath ([string]$sec.file)
        if([string]::IsNullOrWhiteSpace([string]$qfile) -or -not (Test-Path $qfile)){ continue }
        $arr = Read-Json $qfile
        foreach($q in @($arr)){ [void]$pool.Add((Instantiate-Question -q $q -sectionId $sid)) }
    }

    if($pool.Count -eq 0){ [System.Windows.Forms.MessageBox]::Show('No questions found for selected sections.'); return }

    $count = [Math]::Min([int]$numCount.Value, $pool.Count)
    $script:Items = @($pool | Get-Random -Count $count)
    $script:Started = $true
    Show-CurrentQuestion -feedback @('--- New Quiz Session ---')
    $txtInput.Focus()
})

$submitAction = {
    if(-not $script:Started){ return }
    $user = $txtInput.Text.Trim()
    if([string]::IsNullOrWhiteSpace($user)){ return }
    $txtInput.Clear()

    $cur = $script:Items[$script:Index]
    $alts = @()
    if($cur.PSObject.Properties['alternate_answers'] -and $cur.alternate_answers){ $alts = @($cur.alternate_answers | ForEach-Object { [string]$_ }) }
    $ok = Test-Answer -user $user -expected ([string]$cur.answer) -alts $alts

    $feedback = New-Object System.Collections.Generic.List[string]
    if($ok){
        $script:Score++
        $feedback.Add('Correct')
    } else {
        $feedback.Add('Incorrect')
        $feedback.Add(('Your response: {0}' -f $user))
        if(-not $script:IsStory){ $feedback.Add(('Correct response: {0}' -f [string]$cur.answer)) }
    }

    if($script:IsStory){
        if($ok){
            Apply-Outcome -outcome (Get-OptionalProp $cur 'on_correct') -extra $feedback
            $script:Index++
        } else {
            $inc = Get-OptionalProp $cur 'on_incorrect'
            Apply-Outcome -outcome $inc -extra $feedback
            $rew = Get-OptionalProp $inc 'rewind_steps'
            if($null -ne $rew){
                try {
                    $rw = [int]$rew
                    if($rw -gt 0){ $script:Index = [Math]::Max(0, ($script:Index - $rw)) }
                } catch {}
            }
        }
    } else {
        $script:Index++
    }

    Show-CurrentQuestion -feedback $feedback.ToArray()
}

$btnSend.Add_Click($submitAction)
$txtInput.Add_KeyDown({ if($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter){ $_.SuppressKeyPress = $true; & $submitAction } })

Reload-Stories
Load-ManPages
Write-Terminal -lines @(
    'DeadSec Framework initialized.'
) -clear $true

[void]$form.Add_FormClosing({
    if($script:ManForm -and -not $script:ManForm.IsDisposed){
        $script:ManForm.Close()
    }
})

[void]$form.ShowDialog()










