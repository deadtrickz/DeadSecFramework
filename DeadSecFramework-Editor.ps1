Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:Root) { $script:Root = (Get-Location).Path }
$script:QDir = Join-Path $script:Root 'quiz-data\questions'
$script:SDir = Join-Path $script:Root 'quiz-data\stories'
if (-not (Test-Path -LiteralPath $script:SDir)) { $script:SDir = Join-Path $script:Root 'vs-exe-launcher\Stories' }
$script:MDir = if (Test-Path -LiteralPath (Join-Path $script:Root 'Manpages')) { Join-Path $script:Root 'Manpages' } else { Join-Path $script:Root 'quiz-data\man-pages' }

$script:QItems = @()
$script:QFile = $null
$script:SObj = [ordered]@{ id=''; name=''; description=''; steps=@() }
$script:SFile = $null
$script:MFile = $null
$script:LayoutFile = Join-Path $script:Root 'editor-layout.json'
$script:LoadedLayout = $null

function MsgErr([string]$m) {
    [void][System.Windows.Forms.MessageBox]::Show($m, 'DeadSecFramework Editor', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function MsgInfo([string]$m) {
    [void][System.Windows.Forms.MessageBox]::Show($m, 'DeadSecFramework Editor', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Ensure-Dir([string]$d) {
    if (-not (Test-Path -LiteralPath $d)) {
        [void](New-Item -ItemType Directory -Path $d -Force)
    }
}

function Lines-FromText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' })
}

function Show-LineEditor([string]$title, [string]$value) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $title
    $f.StartPosition = 'CenterParent'
    $f.Size = New-Object System.Drawing.Size(950, 170)
    $f.MinimumSize = New-Object System.Drawing.Size(700, 170)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Dock = 'Top'
    $tb.Multiline = $false
    $tb.Height = 30
    $tb.Text = $value
    $f.Controls.Add($tb)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Bottom'
    $panel.Height = 44
    $f.Controls.Add($panel)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Size = New-Object System.Drawing.Size(90, 28)
    $ok.Location = New-Object System.Drawing.Point(740, 8)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $panel.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object System.Drawing.Size(90, 28)
    $cancel.Location = New-Object System.Drawing.Point(838, 8)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $panel.Controls.Add($cancel)

    $f.AcceptButton = $ok
    $f.CancelButton = $cancel

    $res = $f.ShowDialog()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        return $tb.Text.TrimEnd()
    }
    return $null
}

function New-LineGrid([bool]$singleLine = $false) {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.MultiSelect = $false
    $g.SelectionMode = 'FullRowSelect'
    $g.ReadOnly = $true
    $g.RowHeadersVisible = $false
    $g.AutoSizeColumnsMode = 'Fill'
    $g.BackgroundColor = [System.Drawing.Color]::White
    $g.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
    $g.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
    $g.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $g.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0,120,215)
    $g.RowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
    $g.AlternatingRowsDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
    [void]$g.Columns.Add('line', 'Line')
    $g.Columns[0].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    $g.Tag = @{ single = $singleLine }
    return $g
}

function Grid-SetLines($g, [object]$lines) {
    $g.Rows.Clear()
    if ($null -eq $lines) { return }

    $arr = @()
    if ($lines -is [string]) {
        $arr = @([string]$lines)
    }
    elseif ($lines -is [System.Collections.IEnumerable]) {
        foreach ($x in $lines) { $arr += [string]$x }
    }
    else {
        $arr = @([string]$lines)
    }

    foreach ($l in $arr) { [void]$g.Rows.Add($l) }
}

function Grid-GetLines($g) {
    $out = @()
    foreach ($r in $g.Rows) {
        if ($r.IsNewRow) { continue }
        $v = [string]$r.Cells[0].Value
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            $out += $v.TrimEnd()
        }
    }
    return @($out)
}

function Grid-EditSelected($g, [string]$title) {
    if ($g.SelectedRows.Count -eq 0) { return }
    $idx = $g.SelectedRows[0].Index
    $cur = [string]$g.Rows[$idx].Cells[0].Value
    $nv = Show-LineEditor $title $cur
    if ($null -ne $nv) { $g.Rows[$idx].Cells[0].Value = $nv }
}

function Grid-AddLine($g, [string]$title) {
    $single = $false
    if ($g.Tag -and $g.Tag.single) { $single = [bool]$g.Tag.single }
    $nv = Show-LineEditor $title ''
    if ($null -eq $nv) { return }

    if ($single) {
        if ($g.Rows.Count -eq 0) {
            [void]$g.Rows.Add($nv)
        } else {
            $g.Rows[0].Cells[0].Value = $nv
        }
        return
    }

    [void]$g.Rows.Add($nv)
}

function Grid-DeleteSelected($g) {
    if ($g.SelectedRows.Count -eq 0) { return }
    $idx = $g.SelectedRows[0].Index
    if ($idx -ge 0 -and $idx -lt $g.Rows.Count) {
        $g.Rows.RemoveAt($idx)
    }
}

function Write-JsonFile([string]$path, [object]$obj, [int]$depth = 40) {
    $json = $obj | ConvertTo-Json -Depth $depth
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Clamp([int]$value, [int]$min, [int]$max) {
    if ($value -lt $min) { return $min }
    if ($value -gt $max) { return $max }
    return $value
}

function New-QuestionTemplateObject {
    return @(
        [pscustomobject]@{
            question = @(
                'Template question line 1.',
                'Template question line 2 (optional).'
            )
            answer = 'tool --flag <value>'
            alternate_answers = @(
                'tool <value> --flag'
            )
        }
    )
}

function New-StoryTemplateObject {
    return [ordered]@{
        id = 'template_story_001'
        name = 'Template Story'
        description = 'Template story file for DeadSecFramework editor.'
        steps = @(
            [pscustomobject]@{
                question = @(
                    'Recon: Describe what needs to be done.',
                    'Target: 10.10.10.10'
                )
                answer = 'nmap -sV -sC 10.10.10.10'
                alternate_answers = @(
                    'nmap 10.10.10.10 -sV -sC'
                )
                on_correct = [ordered]@{
                    messages = @('Template success message.')
                    beacon_add = @(
                        [ordered]@{
                            id = 'template_beacon_01'
                            ip = '10.10.10.10'
                            hostname = 'host-10'
                            username = 'evilcorp\operator'
                            mac_address = '00:11:22:33:44:55'
                            persistent = $true
                        }
                    )
                }
            }
        )
    }
}

function Add-BeaconTemplateToOnCorrect([bool]$persistent = $false) {
    $id = Show-LineEditor 'Beacon ID' 'beacon_01'
    if ($null -eq $id -or [string]::IsNullOrWhiteSpace($id)) { return }
    $ip = Show-LineEditor 'Beacon IP' '10.10.10.10'
    if ($null -eq $ip -or [string]::IsNullOrWhiteSpace($ip)) { return }
    $host = Show-LineEditor 'Beacon Hostname' 'host-10'
    if ($null -eq $host) { return }
    $user = Show-LineEditor 'Beacon Username' 'evilcorp\user'
    if ($null -eq $user) { return }
    $mac = Show-LineEditor 'Beacon MAC Address' '00:11:22:33:44:55'
    if ($null -eq $mac) { return }

    $obj = [pscustomobject]@{}
    if (-not [string]::IsNullOrWhiteSpace($sOnC.Text)) {
        try {
            $obj = ($sOnC.Text | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            MsgErr("on_correct JSON is invalid.`n$($_.Exception.Message)")
            return
        }
    }

    if (-not $obj.PSObject.Properties['messages']) { $obj | Add-Member -NotePropertyName messages -NotePropertyValue @() }
    if (-not $obj.PSObject.Properties['beacon_add']) { $obj | Add-Member -NotePropertyName beacon_add -NotePropertyValue @() }
    if (-not $obj.PSObject.Properties['beacon_remove']) { $obj | Add-Member -NotePropertyName beacon_remove -NotePropertyValue @() }

    $beacon = [ordered]@{
        id = $id
        ip = $ip
        hostname = $host
        username = $user
        mac_address = $mac
        persistent = $persistent
    }

    $existing = @($obj.beacon_add)
    $existing += [pscustomobject]$beacon
    $obj.beacon_add = $existing

    if ($persistent -and $obj.beacon_remove) {
        $obj.beacon_remove = @($obj.beacon_remove | Where-Object { [string]$_ -ne $id })
    }

    $sOnC.Text = ($obj | ConvertTo-Json -Depth 40)
    Set-Status("Beacon template added: $id (persistent=$persistent)")
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DeadSecFramework Editor'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1500, 900)
$form.MinimumSize = New-Object System.Drawing.Size(1240, 780)
$form.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$mainTabs = New-Object System.Windows.Forms.TabControl
$mainTabs.Dock = 'Fill'
$form.Controls.Add($mainTabs)

$tabQuestions = New-Object System.Windows.Forms.TabPage
$tabQuestions.Text = 'Questions'
$tabQuestions.BackColor = $form.BackColor
$tabQuestions.ForeColor = [System.Drawing.Color]::White
[void]$mainTabs.TabPages.Add($tabQuestions)

$tabStories = New-Object System.Windows.Forms.TabPage
$tabStories.Text = 'Stories'
$tabStories.BackColor = $form.BackColor
$tabStories.ForeColor = [System.Drawing.Color]::White
[void]$mainTabs.TabPages.Add($tabStories)

$tabManPages = New-Object System.Windows.Forms.TabPage
$tabManPages.Text = 'Man Pages'
$tabManPages.BackColor = $form.BackColor
$tabManPages.ForeColor = [System.Drawing.Color]::White
[void]$mainTabs.TabPages.Add($tabManPages)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready.'
[void]$status.Items.Add($statusLabel)
$form.Controls.Add($status)

function Set-Status([string]$m) { $statusLabel.Text = $m }

function Load-LayoutState {
    if (-not (Test-Path -LiteralPath $script:LayoutFile)) { return }
    try {
        $script:LoadedLayout = Get-Content -LiteralPath $script:LayoutFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $script:LoadedLayout = $null
    }
}

function Save-LayoutState {
    try {
        $obj = [ordered]@{
            window = [ordered]@{
                x = $form.Location.X
                y = $form.Location.Y
                width = $form.Width
                height = $form.Height
                state = [string]$form.WindowState
            }
            splitters = [ordered]@{
                questions = $qSplit.SplitterDistance
                stories = $sSplit.SplitterDistance
                man_pages = $mSplit.SplitterDistance
            }
            selected_tab = [string]$mainTabs.SelectedTab.Text
        }
        Write-JsonFile $script:LayoutFile $obj 10
    }
    catch {
        # best effort only
    }
}

function Apply-LayoutState {
    $defaultQ = 390
    $defaultS = 390
    $defaultM = 390

    $qMax = [Math]::Max($qSplit.Panel1MinSize + 1, $qSplit.Width - 60)
    $sMax = [Math]::Max($sSplit.Panel1MinSize + 1, $sSplit.Width - 60)
    $mMax = [Math]::Max($mSplit.Panel1MinSize + 1, $mSplit.Width - 60)

    if ($null -eq $script:LoadedLayout) {
        $qSplit.SplitterDistance = Clamp $defaultQ $qSplit.Panel1MinSize $qMax
        $sSplit.SplitterDistance = Clamp $defaultS $sSplit.Panel1MinSize $sMax
        $mSplit.SplitterDistance = Clamp $defaultM $mSplit.Panel1MinSize $mMax
        $mainTabs.SelectedTab = $tabQuestions
        return
    }

    try {
        if ($script:LoadedLayout.window) {
            if ($script:LoadedLayout.window.width -and $script:LoadedLayout.window.height) {
                $form.Size = New-Object System.Drawing.Size([int]$script:LoadedLayout.window.width, [int]$script:LoadedLayout.window.height)
            }
            if ($script:LoadedLayout.window.x -ne $null -and $script:LoadedLayout.window.y -ne $null) {
                $form.StartPosition = 'Manual'
                $form.Location = New-Object System.Drawing.Point([int]$script:LoadedLayout.window.x, [int]$script:LoadedLayout.window.y)
            }
        }
    } catch {}

    $qDist = $defaultQ
    $sDist = $defaultS
    $mDist = $defaultM
    if ($script:LoadedLayout.splitters) {
        if ($script:LoadedLayout.splitters.questions -ne $null) { $qDist = [int]$script:LoadedLayout.splitters.questions }
        if ($script:LoadedLayout.splitters.stories -ne $null) { $sDist = [int]$script:LoadedLayout.splitters.stories }
        if ($script:LoadedLayout.splitters.man_pages -ne $null) { $mDist = [int]$script:LoadedLayout.splitters.man_pages }
    }

    $qSplit.SplitterDistance = Clamp $qDist $qSplit.Panel1MinSize $qMax
    $sSplit.SplitterDistance = Clamp $sDist $sSplit.Panel1MinSize $sMax
    $mSplit.SplitterDistance = Clamp $mDist $mSplit.Panel1MinSize $mMax

    $targetTab = if ($script:LoadedLayout.selected_tab) { [string]$script:LoadedLayout.selected_tab } else { 'Questions' }
    switch ($targetTab) {
        'Stories' { $mainTabs.SelectedTab = $tabStories }
        'Man Pages' { $mainTabs.SelectedTab = $tabManPages }
        default { $mainTabs.SelectedTab = $tabQuestions }
    }

    if ($script:LoadedLayout.window -and $script:LoadedLayout.window.state -eq 'Maximized') {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
}

# =========================
# Questions tab UI
# =========================
$qLayout = New-Object System.Windows.Forms.TableLayoutPanel
$qLayout.Dock = 'Fill'
$qLayout.RowCount = 2
$qLayout.ColumnCount = 1
[void]$qLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50)))
[void]$qLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tabQuestions.Controls.Add($qLayout)

$qTop = New-Object System.Windows.Forms.Panel
$qTop.Dock = 'Fill'
$qTop.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
$qLayout.Controls.Add($qTop, 0, 0)

$qTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Folder:'; AutoSize=$true; Location=(New-Object System.Drawing.Point(8, 14)) }))
$qPath = New-Object System.Windows.Forms.TextBox
$qPath.Location = New-Object System.Drawing.Point(60, 10)
$qPath.Size = New-Object System.Drawing.Size(700, 28)
$qPath.Text = $script:QDir
$qTop.Controls.Add($qPath)

$qRef = New-Object System.Windows.Forms.Button -Property @{ Text='Refresh'; Size=(New-Object System.Drawing.Size(90, 30)); Location=(New-Object System.Drawing.Point(770, 9)) }
$qNew = New-Object System.Windows.Forms.Button -Property @{ Text='New'; Size=(New-Object System.Drawing.Size(80, 30)); Location=(New-Object System.Drawing.Point(866, 9)) }
$qLoad = New-Object System.Windows.Forms.Button -Property @{ Text='Load'; Size=(New-Object System.Drawing.Size(80, 30)); Location=(New-Object System.Drawing.Point(952, 9)) }
$qSave = New-Object System.Windows.Forms.Button -Property @{ Text='Save'; Size=(New-Object System.Drawing.Size(80, 30)); Location=(New-Object System.Drawing.Point(1038, 9)) }
$qSaveAs = New-Object System.Windows.Forms.Button -Property @{ Text='Save As'; Size=(New-Object System.Drawing.Size(90, 30)); Location=(New-Object System.Drawing.Point(1124, 9)) }
$qTemplate = New-Object System.Windows.Forms.Button -Property @{ Text='Template'; Size=(New-Object System.Drawing.Size(96, 30)); Location=(New-Object System.Drawing.Point(1220, 9)) }
$qTop.Controls.AddRange(@($qRef,$qNew,$qLoad,$qSave,$qSaveAs,$qTemplate))

$qSplit = New-Object System.Windows.Forms.SplitContainer
$qSplit.Dock = 'Fill'
$qSplit.SplitterDistance = 360
$qSplit.Panel1MinSize = 360
$qLayout.Controls.Add($qSplit, 0, 1)

$qLeft = New-Object System.Windows.Forms.TableLayoutPanel
$qLeft.Dock = 'Fill'
$qLeft.RowCount = 4
$qLeft.ColumnCount = 1
[void]$qLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$qLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 40)))
[void]$qLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
[void]$qLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 60)))
$qSplit.Panel1.Controls.Add($qLeft)

$qFilesLbl = New-Object System.Windows.Forms.Label -Property @{ Text='Question Files'; Dock='Fill' }
$qLeft.Controls.Add($qFilesLbl, 0, 0)

$qFiles = New-Object System.Windows.Forms.ListBox
$qFiles.Dock = 'Fill'
$qLeft.Controls.Add($qFiles, 0, 1)

$qHead = New-Object System.Windows.Forms.Panel
$qHead.Dock = 'Fill'
$qLeft.Controls.Add($qHead, 0, 2)
$qHead.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Questions'; AutoSize=$true; Location=(New-Object System.Drawing.Point(0, 6)) }))
$qAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add'; Size=(New-Object System.Drawing.Size(46, 24)); Location=(New-Object System.Drawing.Point(100,2)) }
$qIns = New-Object System.Windows.Forms.Button -Property @{ Text='Insert'; Size=(New-Object System.Drawing.Size(56, 24)); Location=(New-Object System.Drawing.Point(150,2)) }
$qDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete'; Size=(New-Object System.Drawing.Size(58, 24)); Location=(New-Object System.Drawing.Point(210,2)) }
$qUp = New-Object System.Windows.Forms.Button -Property @{ Text='Up'; Size=(New-Object System.Drawing.Size(42, 24)); Location=(New-Object System.Drawing.Point(272,2)) }
$qDn = New-Object System.Windows.Forms.Button -Property @{ Text='Dn'; Size=(New-Object System.Drawing.Size(42, 24)); Location=(New-Object System.Drawing.Point(318,2)) }
$qHead.Controls.AddRange(@($qAdd,$qIns,$qDel,$qUp,$qDn))

$qList = New-Object System.Windows.Forms.ListBox
$qList.Dock = 'Fill'
$qLeft.Controls.Add($qList, 0, 3)
$qRight = New-Object System.Windows.Forms.TableLayoutPanel
$qRight.Dock = 'Fill'
$qRight.RowCount = 4
$qRight.ColumnCount = 1
[void]$qRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 40)))
[void]$qRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 25)))
[void]$qRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
[void]$qRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
$qSplit.Panel2.Controls.Add($qRight)

$qG1 = New-Object System.Windows.Forms.GroupBox
$qG1.Text = 'Question Lines (double-click row to edit full line)'
$qG1.Dock = 'Fill'
$qRight.Controls.Add($qG1, 0, 0)
$qG1L = New-Object System.Windows.Forms.TableLayoutPanel
$qG1L.Dock = 'Fill'
$qG1L.RowCount = 2
$qG1L.ColumnCount = 1
[void]$qG1L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$qG1L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$qG1.Controls.Add($qG1L)
$qQGrid = New-LineGrid $false
$qG1L.Controls.Add($qQGrid, 0, 0)
$qQBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$qQBtns.Dock = 'Fill'
$qQAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add Line'; AutoSize=$true }
$qQDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete Line'; AutoSize=$true }
$qQBtns.Controls.AddRange(@($qQAdd,$qQDel))
$qG1L.Controls.Add($qQBtns, 0, 1)

$qG2 = New-Object System.Windows.Forms.GroupBox
$qG2.Text = 'Answer (single line)'
$qG2.Dock = 'Fill'
$qRight.Controls.Add($qG2, 0, 1)
$qG2L = New-Object System.Windows.Forms.TableLayoutPanel
$qG2L.Dock = 'Fill'
$qG2L.RowCount = 2
$qG2L.ColumnCount = 1
[void]$qG2L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$qG2L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$qG2.Controls.Add($qG2L)
$qAGrid = New-LineGrid $true
$qG2L.Controls.Add($qAGrid, 0, 0)
$qABtns = New-Object System.Windows.Forms.FlowLayoutPanel
$qABtns.Dock = 'Fill'
$qASet = New-Object System.Windows.Forms.Button -Property @{ Text='Set/Replace'; AutoSize=$true }
$qAClear = New-Object System.Windows.Forms.Button -Property @{ Text='Clear'; AutoSize=$true }
$qABtns.Controls.AddRange(@($qASet,$qAClear))
$qG2L.Controls.Add($qABtns, 0, 1)

$qG3 = New-Object System.Windows.Forms.GroupBox
$qG3.Text = 'Alternate Answers (double-click row to edit full line)'
$qG3.Dock = 'Fill'
$qRight.Controls.Add($qG3, 0, 2)
$qG3L = New-Object System.Windows.Forms.TableLayoutPanel
$qG3L.Dock = 'Fill'
$qG3L.RowCount = 2
$qG3L.ColumnCount = 1
[void]$qG3L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$qG3L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$qG3.Controls.Add($qG3L)
$qAltGrid = New-LineGrid $false
$qG3L.Controls.Add($qAltGrid, 0, 0)
$qAltBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$qAltBtns.Dock = 'Fill'
$qAltAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add Alt'; AutoSize=$true }
$qAltDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete Alt'; AutoSize=$true }
$qAltBtns.Controls.AddRange(@($qAltAdd,$qAltDel))
$qG3L.Controls.Add($qAltBtns, 0, 1)

$qApplyPanel = New-Object System.Windows.Forms.Panel
$qApplyPanel.Dock = 'Fill'
$qRight.Controls.Add($qApplyPanel, 0, 3)
$qApply = New-Object System.Windows.Forms.Button
$qApply.Text = 'Apply To Selected Question'
$qApply.Size = New-Object System.Drawing.Size(250, 30)
$qApply.Location = New-Object System.Drawing.Point(8, 4)
$qApplyPanel.Controls.Add($qApply)

# =========================
# Stories tab UI
# =========================
$sLayout = New-Object System.Windows.Forms.TableLayoutPanel
$sLayout.Dock = 'Fill'
$sLayout.RowCount = 2
$sLayout.ColumnCount = 1
[void]$sLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 78)))
[void]$sLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tabStories.Controls.Add($sLayout)

$sTop = New-Object System.Windows.Forms.Panel
$sTop.Dock = 'Fill'
$sTop.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
$sLayout.Controls.Add($sTop, 0, 0)

$sTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Folder:'; AutoSize=$true; Location=(New-Object System.Drawing.Point(8, 14)) }))
$sPath = New-Object System.Windows.Forms.TextBox
$sPath.Location = New-Object System.Drawing.Point(60, 10)
$sPath.Size = New-Object System.Drawing.Size(700, 28)
$sPath.Text = $script:SDir
$sTop.Controls.Add($sPath)

$sRef = New-Object System.Windows.Forms.Button -Property @{ Text='Refresh'; Size=(New-Object System.Drawing.Size(90,30)); Location=(New-Object System.Drawing.Point(770,9)) }
$sNew = New-Object System.Windows.Forms.Button -Property @{ Text='New'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(866,9)) }
$sLoad = New-Object System.Windows.Forms.Button -Property @{ Text='Load'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(952,9)) }
$sSave = New-Object System.Windows.Forms.Button -Property @{ Text='Save'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(1038,9)) }
$sSaveAs = New-Object System.Windows.Forms.Button -Property @{ Text='Save As'; Size=(New-Object System.Drawing.Size(90,30)); Location=(New-Object System.Drawing.Point(1124,9)) }
$sTemplate = New-Object System.Windows.Forms.Button -Property @{ Text='Template'; Size=(New-Object System.Drawing.Size(96,30)); Location=(New-Object System.Drawing.Point(1220,9)) }
$sTop.Controls.AddRange(@($sRef,$sNew,$sLoad,$sSave,$sSaveAs,$sTemplate))

$sTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='id'; AutoSize=$true; Location=(New-Object System.Drawing.Point(8, 50)) }))
$sId = New-Object System.Windows.Forms.TextBox -Property @{ Location=(New-Object System.Drawing.Point(26,46)); Size=(New-Object System.Drawing.Size(220,26)) }
$sTop.Controls.Add($sId)
$sTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='name'; AutoSize=$true; Location=(New-Object System.Drawing.Point(252, 50)) }))
$sName = New-Object System.Windows.Forms.TextBox -Property @{ Location=(New-Object System.Drawing.Point(300,46)); Size=(New-Object System.Drawing.Size(220,26)) }
$sTop.Controls.Add($sName)
$sTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='description'; AutoSize=$true; Location=(New-Object System.Drawing.Point(526, 50)) }))
$sDesc = New-Object System.Windows.Forms.TextBox -Property @{ Location=(New-Object System.Drawing.Point(610,46)); Size=(New-Object System.Drawing.Size(604,26)) }
$sTop.Controls.Add($sDesc)

$sSplit = New-Object System.Windows.Forms.SplitContainer
$sSplit.Dock = 'Fill'
$sSplit.SplitterDistance = 360
$sSplit.Panel1MinSize = 360
$sLayout.Controls.Add($sSplit, 0, 1)

$sLeft = New-Object System.Windows.Forms.TableLayoutPanel
$sLeft.Dock = 'Fill'
$sLeft.RowCount = 4
$sLeft.ColumnCount = 1
[void]$sLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$sLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 40)))
[void]$sLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
[void]$sLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 60)))
$sSplit.Panel1.Controls.Add($sLeft)

$sLeft.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Story Files'; Dock='Fill' }), 0, 0)
$sFiles = New-Object System.Windows.Forms.ListBox
$sFiles.Dock = 'Fill'
$sLeft.Controls.Add($sFiles, 0, 1)

$sHead = New-Object System.Windows.Forms.Panel
$sHead.Dock = 'Fill'
$sLeft.Controls.Add($sHead, 0, 2)
$sHead.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Steps'; AutoSize=$true; Location=(New-Object System.Drawing.Point(0,6)) }))
$sAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add'; Size=(New-Object System.Drawing.Size(46,24)); Location=(New-Object System.Drawing.Point(70,2)) }
$sIns = New-Object System.Windows.Forms.Button -Property @{ Text='Insert'; Size=(New-Object System.Drawing.Size(56,24)); Location=(New-Object System.Drawing.Point(120,2)) }
$sDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete'; Size=(New-Object System.Drawing.Size(58,24)); Location=(New-Object System.Drawing.Point(180,2)) }
$sUp = New-Object System.Windows.Forms.Button -Property @{ Text='Up'; Size=(New-Object System.Drawing.Size(42,24)); Location=(New-Object System.Drawing.Point(242,2)) }
$sDn = New-Object System.Windows.Forms.Button -Property @{ Text='Dn'; Size=(New-Object System.Drawing.Size(42,24)); Location=(New-Object System.Drawing.Point(288,2)) }
$sHead.Controls.AddRange(@($sAdd,$sIns,$sDel,$sUp,$sDn))

$sList = New-Object System.Windows.Forms.ListBox
$sList.Dock = 'Fill'
$sLeft.Controls.Add($sList, 0, 3)
$sRight = New-Object System.Windows.Forms.TableLayoutPanel
$sRight.Dock = 'Fill'
$sRight.RowCount = 5
$sRight.ColumnCount = 1
[void]$sRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 30)))
[void]$sRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 18)))
[void]$sRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 22)))
[void]$sRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 30)))
[void]$sRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
$sSplit.Panel2.Controls.Add($sRight)

$sG1 = New-Object System.Windows.Forms.GroupBox
$sG1.Text = 'Step Question Lines (double-click row to edit full line)'
$sG1.Dock = 'Fill'
$sRight.Controls.Add($sG1, 0, 0)
$sG1L = New-Object System.Windows.Forms.TableLayoutPanel
$sG1L.Dock = 'Fill'
$sG1L.RowCount = 2
$sG1L.ColumnCount = 1
[void]$sG1L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$sG1L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$sG1.Controls.Add($sG1L)
$sQGrid = New-LineGrid $false
$sG1L.Controls.Add($sQGrid, 0, 0)
$sQBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$sQBtns.Dock = 'Fill'
$sQAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add Line'; AutoSize=$true }
$sQDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete Line'; AutoSize=$true }
$sQBtns.Controls.AddRange(@($sQAdd,$sQDel))
$sG1L.Controls.Add($sQBtns, 0, 1)

$sG2 = New-Object System.Windows.Forms.GroupBox
$sG2.Text = 'Answer (single line)'
$sG2.Dock = 'Fill'
$sRight.Controls.Add($sG2, 0, 1)
$sG2L = New-Object System.Windows.Forms.TableLayoutPanel
$sG2L.Dock = 'Fill'
$sG2L.RowCount = 2
$sG2L.ColumnCount = 1
[void]$sG2L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$sG2L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$sG2.Controls.Add($sG2L)
$sAGrid = New-LineGrid $true
$sG2L.Controls.Add($sAGrid, 0, 0)
$sABtns = New-Object System.Windows.Forms.FlowLayoutPanel
$sABtns.Dock = 'Fill'
$sASet = New-Object System.Windows.Forms.Button -Property @{ Text='Set/Replace'; AutoSize=$true }
$sAClear = New-Object System.Windows.Forms.Button -Property @{ Text='Clear'; AutoSize=$true }
$sABtns.Controls.AddRange(@($sASet,$sAClear))
$sG2L.Controls.Add($sABtns, 0, 1)

$sG3 = New-Object System.Windows.Forms.GroupBox
$sG3.Text = 'Alternate Answers (double-click row to edit full line)'
$sG3.Dock = 'Fill'
$sRight.Controls.Add($sG3, 0, 2)
$sG3L = New-Object System.Windows.Forms.TableLayoutPanel
$sG3L.Dock = 'Fill'
$sG3L.RowCount = 2
$sG3L.ColumnCount = 1
[void]$sG3L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$sG3L.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$sG3.Controls.Add($sG3L)
$sAltGrid = New-LineGrid $false
$sG3L.Controls.Add($sAltGrid, 0, 0)
$sAltBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$sAltBtns.Dock = 'Fill'
$sAltAdd = New-Object System.Windows.Forms.Button -Property @{ Text='Add Alt'; AutoSize=$true }
$sAltDel = New-Object System.Windows.Forms.Button -Property @{ Text='Delete Alt'; AutoSize=$true }
$sAltBtns.Controls.AddRange(@($sAltAdd,$sAltDel))
$sG3L.Controls.Add($sAltBtns, 0, 1)

$sBottom = New-Object System.Windows.Forms.TableLayoutPanel
$sBottom.Dock = 'Fill'
$sBottom.RowCount = 2
$sBottom.ColumnCount = 2
[void]$sBottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$sBottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$sBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$sBottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$sRight.Controls.Add($sBottom, 0, 3)

$sBottom.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='on_correct JSON'; Dock='Fill' }), 0, 0)
$sBottom.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='on_incorrect JSON'; Dock='Fill' }), 1, 0)
$sOnC = New-Object System.Windows.Forms.TextBox -Property @{ Multiline=$true; ScrollBars='Both'; WordWrap=$false; Dock='Fill' }
$sOnI = New-Object System.Windows.Forms.TextBox -Property @{ Multiline=$true; ScrollBars='Both'; WordWrap=$false; Dock='Fill' }
$sBottom.Controls.Add($sOnC, 0, 1)
$sBottom.Controls.Add($sOnI, 1, 1)

$sBtnPanel = New-Object System.Windows.Forms.Panel
$sBtnPanel.Dock = 'Fill'
$sBtnPanel.Height = 38
$sRight.Controls.Add($sBtnPanel, 0, 4)
$sApply = New-Object System.Windows.Forms.Button -Property @{ Text='Apply Step'; Size=(New-Object System.Drawing.Size(150,30)); Location=(New-Object System.Drawing.Point(8,4)) }
$sApplyMeta = New-Object System.Windows.Forms.Button -Property @{ Text='Apply Metadata'; Size=(New-Object System.Drawing.Size(170,30)); Location=(New-Object System.Drawing.Point(164,4)) }
$sBeaconPersistent = New-Object System.Windows.Forms.CheckBox -Property @{ Text='Persistent Beacon'; AutoSize=$true; Location=(New-Object System.Drawing.Point(342,10)); ForeColor=[System.Drawing.Color]::White; BackColor=[System.Drawing.Color]::Transparent }
$sAddBeacon = New-Object System.Windows.Forms.Button -Property @{ Text='Add Beacon'; Size=(New-Object System.Drawing.Size(120,30)); Location=(New-Object System.Drawing.Point(490,4)) }
$sBtnPanel.Controls.AddRange(@($sApply,$sApplyMeta,$sBeaconPersistent,$sAddBeacon))

# =========================
# Man Pages tab UI
# =========================
$mLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mLayout.Dock = 'Fill'
$mLayout.RowCount = 2
$mLayout.ColumnCount = 1
[void]$mLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50)))
[void]$mLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tabManPages.Controls.Add($mLayout)

$mTop = New-Object System.Windows.Forms.Panel
$mTop.Dock = 'Fill'
$mTop.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
$mLayout.Controls.Add($mTop, 0, 0)
$mTop.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Folder:'; AutoSize=$true; Location=(New-Object System.Drawing.Point(8, 14)) }))
$mPath = New-Object System.Windows.Forms.TextBox -Property @{ Location=(New-Object System.Drawing.Point(60,10)); Size=(New-Object System.Drawing.Size(700,28)); Text=$script:MDir }
$mTop.Controls.Add($mPath)
$mRef = New-Object System.Windows.Forms.Button -Property @{ Text='Refresh'; Size=(New-Object System.Drawing.Size(90,30)); Location=(New-Object System.Drawing.Point(770,9)) }
$mNew = New-Object System.Windows.Forms.Button -Property @{ Text='New'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(866,9)) }
$mLoad = New-Object System.Windows.Forms.Button -Property @{ Text='Load'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(952,9)) }
$mSave = New-Object System.Windows.Forms.Button -Property @{ Text='Save'; Size=(New-Object System.Drawing.Size(80,30)); Location=(New-Object System.Drawing.Point(1038,9)) }
$mSaveAs = New-Object System.Windows.Forms.Button -Property @{ Text='Save As'; Size=(New-Object System.Drawing.Size(90,30)); Location=(New-Object System.Drawing.Point(1124,9)) }
$mDelete = New-Object System.Windows.Forms.Button -Property @{ Text='Delete'; Size=(New-Object System.Drawing.Size(90,30)); Location=(New-Object System.Drawing.Point(1220,9)) }
$mTop.Controls.AddRange(@($mRef,$mNew,$mLoad,$mSave,$mSaveAs,$mDelete))

$mSplit = New-Object System.Windows.Forms.SplitContainer
$mSplit.Dock = 'Fill'
$mSplit.SplitterDistance = 360
$mSplit.Panel1MinSize = 300
$mLayout.Controls.Add($mSplit, 0, 1)

$mLeft = New-Object System.Windows.Forms.TableLayoutPanel
$mLeft.Dock = 'Fill'
$mLeft.RowCount = 2
$mLeft.ColumnCount = 1
[void]$mLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$mLeft.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mSplit.Panel1.Controls.Add($mLeft)
$mLeft.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Man Page Files (*.txt)'; Dock='Fill' }), 0, 0)
$mFiles = New-Object System.Windows.Forms.ListBox
$mFiles.Dock = 'Fill'
$mLeft.Controls.Add($mFiles, 0, 1)

$mRight = New-Object System.Windows.Forms.TableLayoutPanel
$mRight.Dock = 'Fill'
$mRight.RowCount = 2
$mRight.ColumnCount = 1
[void]$mRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
[void]$mRight.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mSplit.Panel2.Controls.Add($mRight)
$mRight.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text='Man Page Content'; Dock='Fill' }), 0, 0)
$mText = New-Object System.Windows.Forms.TextBox
$mText.Multiline = $true
$mText.ScrollBars = 'Both'
$mText.WordWrap = $false
$mText.Font = New-Object System.Drawing.Font('Consolas', 10)
$mText.AcceptsTab = $true
$mText.Dock = 'Fill'
$mRight.Controls.Add($mText, 0, 1)

# =========================
# Question functions
# =========================
function Refresh-QFiles {
    Ensure-Dir $qPath.Text
    $script:QDir = $qPath.Text
    $qFiles.Items.Clear()
    Get-ChildItem -LiteralPath $script:QDir -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
        [void]$qFiles.Items.Add($_.Name)
    }
    Set-Status("Question files: $($qFiles.Items.Count)")
}

function Refresh-QList {
    $qList.Items.Clear()
    for ($i=0; $i -lt $script:QItems.Count; $i++) {
        $it = $script:QItems[$i]
        $p = ''
        if ($it.PSObject.Properties['question'] -and $it.question -and $it.question.Count -gt 0) { $p = [string]$it.question[0] }
        if ($p.Length -gt 95) { $p = $p.Substring(0,95) + '...' }
        [void]$qList.Items.Add(('{0:D3}: {1}' -f ($i+1), $p))
    }
    if ($qList.Items.Count -gt 0 -and $qList.SelectedIndex -lt 0) { $qList.SelectedIndex = 0 }
}

function Load-QFile([string]$path) {
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $j = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $j) { $j = @() }
        if ($j -isnot [array]) { MsgErr 'Question file must be a JSON array.'; return }
        $script:QItems = @($j)
        $script:QFile = $path
        Refresh-QList
        if ($qList.Items.Count -gt 0) { $qList.SelectedIndex = 0; Pull-QToEditor 0 }
        Set-Status("Loaded: $([IO.Path]::GetFileName($path))")
    }
    catch { MsgErr("Failed to load questions.`n$($_.Exception.Message)") }
}

function Save-QFile([string]$path) {
    try {
        $json = $script:QItems | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
        $script:QFile = $path
        Set-Status("Saved: $([IO.Path]::GetFileName($path))")
    }
    catch { MsgErr("Failed to save questions.`n$($_.Exception.Message)") }
}

function Pull-QToEditor([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:QItems.Count) {
        Grid-SetLines $qQGrid @()
        Grid-SetLines $qAGrid @()
        Grid-SetLines $qAltGrid @()
        return
    }

    $it = $script:QItems[$idx]
    $qLines = @()
    if ($it.PSObject.Properties['question']) {
        if ($it.question -is [string]) { $qLines = @([string]$it.question) }
        elseif ($it.question -is [System.Collections.IEnumerable]) { foreach ($x in $it.question) { $qLines += [string]$x } }
        else { $qLines = @([string]$it.question) }
    }

    Grid-SetLines $qQGrid $qLines
    Grid-SetLines $qAGrid @([string]$it.answer)
    if ($it.PSObject.Properties['alternate_answers']) { Grid-SetLines $qAltGrid $it.alternate_answers } else { Grid-SetLines $qAltGrid @() }
    Set-Status("Loaded question lines: $($qLines.Count)")
}

function Push-QFromEditor([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:QItems.Count) { MsgErr 'Select a question first.'; return }

    $qLines = Grid-GetLines $qQGrid
    if ($qLines.Count -eq 0) { MsgErr 'Question lines cannot be empty.'; return }

    $aLines = Grid-GetLines $qAGrid
    if ($aLines.Count -eq 0) { MsgErr 'Answer cannot be empty.'; return }
    if ($aLines.Count -gt 1) { MsgErr 'Answer supports one line. Keep only one.'; return }

    $o = [ordered]@{
        question = @($qLines)
        answer = [string]$aLines[0]
    }

    $alts = Grid-GetLines $qAltGrid
    if ($alts.Count -gt 0) { $o.alternate_answers = @($alts) }

    $script:QItems[$idx] = [pscustomobject]$o
    Refresh-QList
    $qList.SelectedIndex = $idx
}

function New-QItem { return [pscustomobject]([ordered]@{ question=@('New question line'); answer='command here' }) }
# =========================
# Story functions
# =========================
function Refresh-SFiles {
    Ensure-Dir $sPath.Text
    $script:SDir = $sPath.Text
    $sFiles.Items.Clear()
    Get-ChildItem -LiteralPath $script:SDir -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
        [void]$sFiles.Items.Add($_.Name)
    }
    Set-Status("Story files: $($sFiles.Items.Count)")
}

function Pull-SMeta {
    $sId.Text = [string]$script:SObj.id
    $sName.Text = [string]$script:SObj.name
    $sDesc.Text = [string]$script:SObj.description
}

function Push-SMeta {
    $script:SObj.id = $sId.Text.Trim()
    $script:SObj.name = $sName.Text.Trim()
    $script:SObj.description = $sDesc.Text.Trim()
}

function Refresh-SList {
    $sList.Items.Clear()
    $steps = @($script:SObj.steps)
    for ($i=0; $i -lt $steps.Count; $i++) {
        $p = ''
        if ($steps[$i].PSObject.Properties['question'] -and $steps[$i].question -and $steps[$i].question.Count -gt 0) { $p = [string]$steps[$i].question[0] }
        if ($p.Length -gt 95) { $p = $p.Substring(0,95) + '...' }
        [void]$sList.Items.Add(('{0:D3}: {1}' -f ($i+1), $p))
    }
    if ($sList.Items.Count -gt 0 -and $sList.SelectedIndex -lt 0) { $sList.SelectedIndex = 0 }
}

function Load-SFile([string]$path) {
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $j = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $j.PSObject.Properties['steps']) { MsgErr 'Story JSON must contain steps.'; return }
        $steps = @(); if ($j.steps) { $steps = @($j.steps) }
        $script:SObj = [ordered]@{ id=[string]$j.id; name=[string]$j.name; description=[string]$j.description; steps=$steps }
        $script:SFile = $path
        Pull-SMeta
        Refresh-SList
        Set-Status("Loaded: $([IO.Path]::GetFileName($path))")
    }
    catch { MsgErr("Failed to load story.`n$($_.Exception.Message)") }
}

function Save-SFile([string]$path) {
    Push-SMeta
    $o = [ordered]@{ id=$script:SObj.id; name=$script:SObj.name; description=$script:SObj.description; steps=@($script:SObj.steps) }
    try {
        $json = $o | ConvertTo-Json -Depth 40
        [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
        $script:SFile = $path
        Set-Status("Saved: $([IO.Path]::GetFileName($path))")
    }
    catch { MsgErr("Failed to save story.`n$($_.Exception.Message)") }
}

function Pull-SToEditor([int]$idx) {
    $steps = @($script:SObj.steps)
    if ($idx -lt 0 -or $idx -ge $steps.Count) {
        Grid-SetLines $sQGrid @()
        Grid-SetLines $sAGrid @()
        Grid-SetLines $sAltGrid @()
        $sOnC.Text='';$sOnI.Text=''
        return
    }
    $st = $steps[$idx]
    Grid-SetLines $sQGrid $st.question
    Grid-SetLines $sAGrid @([string]$st.answer)
    if ($st.PSObject.Properties['alternate_answers']) { Grid-SetLines $sAltGrid $st.alternate_answers } else { Grid-SetLines $sAltGrid @() }
    if ($st.PSObject.Properties['on_correct']) { $sOnC.Text = ($st.on_correct | ConvertTo-Json -Depth 40) } else { $sOnC.Text = '' }
    if ($st.PSObject.Properties['on_incorrect']) { $sOnI.Text = ($st.on_incorrect | ConvertTo-Json -Depth 40) } else { $sOnI.Text = '' }
}

function Push-SFromEditor([int]$idx) {
    $steps = @($script:SObj.steps)
    if ($idx -lt 0 -or $idx -ge $steps.Count) { MsgErr 'Select a story step first.'; return }

    $qLines = Grid-GetLines $sQGrid
    if ($qLines.Count -eq 0) { MsgErr 'Step question lines cannot be empty.'; return }

    $aLines = Grid-GetLines $sAGrid
    if ($aLines.Count -eq 0) { MsgErr 'Step answer cannot be empty.'; return }
    if ($aLines.Count -gt 1) { MsgErr 'Step answer supports one line. Keep only one.'; return }

    $o = [ordered]@{ question=@($qLines); answer=[string]$aLines[0] }
    $alts = Grid-GetLines $sAltGrid
    if ($alts.Count -gt 0) { $o.alternate_answers = @($alts) }

    if (-not [string]::IsNullOrWhiteSpace($sOnC.Text)) {
        try { $o.on_correct = ($sOnC.Text | ConvertFrom-Json -ErrorAction Stop) }
        catch { MsgErr("on_correct invalid JSON.`n$($_.Exception.Message)"); return }
    }

    if (-not [string]::IsNullOrWhiteSpace($sOnI.Text)) {
        try { $o.on_incorrect = ($sOnI.Text | ConvertFrom-Json -ErrorAction Stop) }
        catch { MsgErr("on_incorrect invalid JSON.`n$($_.Exception.Message)"); return }
    }

    $steps[$idx] = [pscustomobject]$o
    $script:SObj.steps = $steps
    Refresh-SList
    $sList.SelectedIndex = $idx
}

function New-Step { return [pscustomobject]([ordered]@{ question=@('New story step line'); answer='command here' }) }

function Refresh-MFiles {
    Ensure-Dir $mPath.Text
    $script:MDir = $mPath.Text
    $mFiles.Items.Clear()
    Get-ChildItem -LiteralPath $script:MDir -File -Filter '*.txt' | Sort-Object Name | ForEach-Object {
        [void]$mFiles.Items.Add($_.Name)
    }
    Set-Status("Man pages: $($mFiles.Items.Count)")
}

function Format-ManPageForDisplay([string]$raw) {
    if ($null -eq $raw) { return '' }
    $txt = $raw -replace "`t", '    '
    $txt = $txt -replace "`r`n", "`n"
    $txt = $txt -replace "`r", "`n"

    $linesOut = New-Object System.Collections.Generic.List[string]
    $maxWidth = 140
    foreach ($line in ($txt -split "`n")) {
        $l = $line.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($l)) {
            $linesOut.Add('')
            continue
        }

        # Normalize pathological spacing from scraped sources.
        $l = $l -replace ' {3,}', ' '

        if ($l.Length -le $maxWidth) {
            $linesOut.Add($l)
            continue
        }

        # Soft wrap long lines at word boundaries for readability.
        $rest = $l
        while ($rest.Length -gt $maxWidth) {
            $cut = $rest.LastIndexOf(' ', $maxWidth)
            if ($cut -lt 1) { $cut = $maxWidth }
            $chunk = $rest.Substring(0, $cut).TrimEnd()
            $linesOut.Add($chunk)
            $rest = $rest.Substring($cut).TrimStart()
        }
        if ($rest.Length -gt 0) { $linesOut.Add($rest) }
    }

    return ($linesOut -join "`r`n")
}

function Load-MFile([string]$path) {
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $mText.Text = Format-ManPageForDisplay $raw
        $script:MFile = $path
        Set-Status("Loaded man page: $([IO.Path]::GetFileName($path))")
    }
    catch {
        MsgErr("Failed to load man page.`n$($_.Exception.Message)")
    }
}

function Save-MFile([string]$path) {
    try {
        [IO.File]::WriteAllText($path, $mText.Text, (New-Object Text.UTF8Encoding($false)))
        $script:MFile = $path
        Set-Status("Saved man page: $([IO.Path]::GetFileName($path))")
    }
    catch {
        MsgErr("Failed to save man page.`n$($_.Exception.Message)")
    }
}

# =========================
# Events
# =========================
$qRef.Add_Click({ Refresh-QFiles })
$qNew.Add_Click({
    Ensure-Dir $qPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $qPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    $dlg.FileName = 'new-questions.json'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:QItems = @()
        Save-QFile $dlg.FileName
        Refresh-QFiles
        $qFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
        Refresh-QList
    }
})
$qTemplate.Add_Click({
    Ensure-Dir $qPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $qPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    $dlg.FileName = 'question-template.json'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-JsonFile $dlg.FileName (New-QuestionTemplateObject) 20
        Refresh-QFiles
        $qFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
        Load-QFile $dlg.FileName
    }
})
$qLoad.Add_Click({ if ($qFiles.SelectedItem) { Load-QFile (Join-Path $qPath.Text ([string]$qFiles.SelectedItem)) } else { MsgErr 'Select a question file first.' } })
$qSave.Add_Click({ if ($script:QFile) { Save-QFile $script:QFile; Refresh-QFiles } else { MsgErr 'No loaded question file. Use Save As.' } })
$qSaveAs.Add_Click({
    Ensure-Dir $qPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $qPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    if ($script:QFile) { $dlg.FileName = [IO.Path]::GetFileName($script:QFile) }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Save-QFile $dlg.FileName
        Refresh-QFiles
        $qFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
    }
})
$qFiles.Add_DoubleClick({ if ($qFiles.SelectedItem) { Load-QFile (Join-Path $qPath.Text ([string]$qFiles.SelectedItem)) } })
$qList.Add_SelectedIndexChanged({ Pull-QToEditor $qList.SelectedIndex })
$qApply.Add_Click({ Push-QFromEditor $qList.SelectedIndex })
$qAdd.Add_Click({ $script:QItems = @($script:QItems + (New-QItem)); Refresh-QList; $qList.SelectedIndex = $script:QItems.Count - 1 })
$qIns.Add_Click({ $idx = $qList.SelectedIndex; if ($idx -lt 0) { $idx = 0 }; $al = New-Object System.Collections.ArrayList; [void]$al.AddRange($script:QItems); [void]$al.Insert($idx, (New-QItem)); $script:QItems = @($al.ToArray()); Refresh-QList; $qList.SelectedIndex = $idx })
$qDel.Add_Click({ $idx = $qList.SelectedIndex; if ($idx -lt 0 -or $idx -ge $script:QItems.Count) { return }; $al = New-Object System.Collections.ArrayList; [void]$al.AddRange($script:QItems); $al.RemoveAt($idx); $script:QItems = @($al.ToArray()); Refresh-QList })
$qUp.Add_Click({ $i = $qList.SelectedIndex; if ($i -le 0) { return }; $t = $script:QItems[$i-1]; $script:QItems[$i-1] = $script:QItems[$i]; $script:QItems[$i] = $t; Refresh-QList; $qList.SelectedIndex = $i-1 })
$qDn.Add_Click({ $i = $qList.SelectedIndex; if ($i -lt 0 -or $i -ge ($script:QItems.Count-1)) { return }; $t = $script:QItems[$i+1]; $script:QItems[$i+1] = $script:QItems[$i]; $script:QItems[$i] = $t; Refresh-QList; $qList.SelectedIndex = $i+1 })

$qQAdd.Add_Click({ Grid-AddLine $qQGrid 'Edit Question Line' })
$qQDel.Add_Click({ Grid-DeleteSelected $qQGrid })
$qQGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $qQGrid 'Edit Question Line' } })
$qASet.Add_Click({ Grid-AddLine $qAGrid 'Set Answer Line' })
$qAClear.Add_Click({ Grid-SetLines $qAGrid @() })
$qAGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $qAGrid 'Edit Answer Line' } })
$qAltAdd.Add_Click({ Grid-AddLine $qAltGrid 'Edit Alternate Answer' })
$qAltDel.Add_Click({ Grid-DeleteSelected $qAltGrid })
$qAltGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $qAltGrid 'Edit Alternate Answer' } })

$sQAdd.Add_Click({ Grid-AddLine $sQGrid 'Edit Story Step Question Line' })
$sQDel.Add_Click({ Grid-DeleteSelected $sQGrid })
$sQGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $sQGrid 'Edit Story Step Question Line' } })
$sASet.Add_Click({ Grid-AddLine $sAGrid 'Set Story Step Answer' })
$sAClear.Add_Click({ Grid-SetLines $sAGrid @() })
$sAGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $sAGrid 'Edit Story Step Answer' } })
$sAltAdd.Add_Click({ Grid-AddLine $sAltGrid 'Edit Story Step Alternate Answer' })
$sAltDel.Add_Click({ Grid-DeleteSelected $sAltGrid })
$sAltGrid.Add_CellDoubleClick({ param($sender,$e) if ($e.RowIndex -ge 0) { Grid-EditSelected $sAltGrid 'Edit Story Step Alternate Answer' } })

$sRef.Add_Click({ Refresh-SFiles })
$sNew.Add_Click({
    Ensure-Dir $sPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $sPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    $dlg.FileName = 'story-new.json'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:SObj = [ordered]@{ id=''; name=''; description=''; steps=@() }
        Save-SFile $dlg.FileName
        Refresh-SFiles
        $sFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
        Pull-SMeta
        Refresh-SList
    }
})
$sTemplate.Add_Click({
    Ensure-Dir $sPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $sPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    $dlg.FileName = 'story-template.json'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Write-JsonFile $dlg.FileName (New-StoryTemplateObject) 40
        Refresh-SFiles
        $sFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
        Load-SFile $dlg.FileName
    }
})
$sLoad.Add_Click({ if ($sFiles.SelectedItem) { Load-SFile (Join-Path $sPath.Text ([string]$sFiles.SelectedItem)) } else { MsgErr 'Select a story file first.' } })
$sSave.Add_Click({ if ($script:SFile) { Save-SFile $script:SFile; Refresh-SFiles } else { MsgErr 'No loaded story file. Use Save As.' } })
$sSaveAs.Add_Click({
    Ensure-Dir $sPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $sPath.Text
    $dlg.Filter = 'JSON files (*.json)|*.json'
    if ($script:SFile) { $dlg.FileName = [IO.Path]::GetFileName($script:SFile) }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Save-SFile $dlg.FileName
        Refresh-SFiles
        $sFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
    }
})
$sFiles.Add_DoubleClick({ if ($sFiles.SelectedItem) { Load-SFile (Join-Path $sPath.Text ([string]$sFiles.SelectedItem)) } })
$sApplyMeta.Add_Click({ Push-SMeta; Set-Status 'Story metadata applied.' })
$sAddBeacon.Add_Click({ Add-BeaconTemplateToOnCorrect ([bool]$sBeaconPersistent.Checked) })
$sList.Add_SelectedIndexChanged({ Pull-SToEditor $sList.SelectedIndex })
$sApply.Add_Click({ Push-SFromEditor $sList.SelectedIndex })
$sAdd.Add_Click({ $st=@($script:SObj.steps); $st += (New-Step); $script:SObj.steps = $st; Refresh-SList; $sList.SelectedIndex = $st.Count - 1 })
$sIns.Add_Click({ $idx=$sList.SelectedIndex; if($idx -lt 0){$idx=0}; $al=New-Object System.Collections.ArrayList; [void]$al.AddRange(@($script:SObj.steps)); [void]$al.Insert($idx,(New-Step)); $script:SObj.steps=@($al.ToArray()); Refresh-SList; $sList.SelectedIndex=$idx })
$sDel.Add_Click({ $idx=$sList.SelectedIndex; $st=@($script:SObj.steps); if($idx -lt 0 -or $idx -ge $st.Count){return}; $al=New-Object System.Collections.ArrayList; [void]$al.AddRange($st); $al.RemoveAt($idx); $script:SObj.steps=@($al.ToArray()); Refresh-SList })
$sUp.Add_Click({ $i=$sList.SelectedIndex; $st=@($script:SObj.steps); if($i -le 0){return}; $t=$st[$i-1]; $st[$i-1]=$st[$i]; $st[$i]=$t; $script:SObj.steps=$st; Refresh-SList; $sList.SelectedIndex=$i-1 })
$sDn.Add_Click({ $i=$sList.SelectedIndex; $st=@($script:SObj.steps); if($i -lt 0 -or $i -ge ($st.Count-1)){return}; $t=$st[$i+1]; $st[$i+1]=$st[$i]; $st[$i]=$t; $script:SObj.steps=$st; Refresh-SList; $sList.SelectedIndex=$i+1 })

$mRef.Add_Click({ Refresh-MFiles })
$mNew.Add_Click({
    Ensure-Dir $mPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $mPath.Text
    $dlg.Filter = 'Text files (*.txt)|*.txt'
    $dlg.FileName = 'new-tool.txt'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [IO.File]::WriteAllText($dlg.FileName, "TOOL: new-tool`r`nSOURCE_TYPE: custom`r`nSOURCE_URL: `r`nFETCHED_UTC: `r`n`r`nNAME`r`n    new-tool - description here`r`n`r`nSYNOPSIS`r`n    new-tool [options]`r`n`r`nEXAMPLE`r`n    new-tool [Target]", (New-Object Text.UTF8Encoding($false)))
        Refresh-MFiles
        $mFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
        Load-MFile $dlg.FileName
    }
})
$mLoad.Add_Click({ if ($mFiles.SelectedItem) { Load-MFile (Join-Path $mPath.Text ([string]$mFiles.SelectedItem)) } else { MsgErr 'Select a man page file first.' } })
$mSave.Add_Click({ if ($script:MFile) { Save-MFile $script:MFile; Refresh-MFiles } else { MsgErr 'No loaded man page file. Use Save As.' } })
$mSaveAs.Add_Click({
    Ensure-Dir $mPath.Text
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.InitialDirectory = $mPath.Text
    $dlg.Filter = 'Text files (*.txt)|*.txt'
    if ($script:MFile) { $dlg.FileName = [IO.Path]::GetFileName($script:MFile) }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Save-MFile $dlg.FileName
        Refresh-MFiles
        $mFiles.SelectedItem = [IO.Path]::GetFileName($dlg.FileName)
    }
})
$mDelete.Add_Click({
    if (-not $mFiles.SelectedItem) { MsgErr 'Select a man page file first.'; return }
    $path = Join-Path $mPath.Text ([string]$mFiles.SelectedItem)
    if (-not (Test-Path -LiteralPath $path)) { return }
    $res = [System.Windows.Forms.MessageBox]::Show("Delete $([IO.Path]::GetFileName($path))?", 'DeadSecFramework Editor', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
        Remove-Item -LiteralPath $path -Force
        if ($script:MFile -eq $path) { $script:MFile = $null; $mText.Text = '' }
        Refresh-MFiles
    }
})
$mFiles.Add_DoubleClick({ if ($mFiles.SelectedItem) { Load-MFile (Join-Path $mPath.Text ([string]$mFiles.SelectedItem)) } })

# init
Ensure-Dir $script:QDir
Ensure-Dir $script:SDir
Ensure-Dir $script:MDir
Load-LayoutState
Refresh-QFiles
Refresh-SFiles
Refresh-MFiles
if ($qFiles.Items.Count -gt 0) {
    $qFiles.SelectedIndex = 0
    Load-QFile (Join-Path $qPath.Text ([string]$qFiles.SelectedItem))
}
if ($sFiles.Items.Count -gt 0) {
    $sFiles.SelectedIndex = 0
    Load-SFile (Join-Path $sPath.Text ([string]$sFiles.SelectedItem))
}

$form.Add_Shown({
    Apply-LayoutState
})

$form.Add_FormClosing({
    Save-LayoutState
})

Set-Status 'Ready.'
[void]$form.ShowDialog()



