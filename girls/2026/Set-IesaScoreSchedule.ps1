$ErrorActionPreference = 'Stop'
$name = 'IESA 2026 Score Refresh'
$task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
$expected = Join-Path $PSScriptRoot 'Update-IesaScores.ps1'
if ($task.Actions.Count -ne 1 -or $task.Actions[0].Arguments -notlike "*$expected*") {
    throw "The $name task does not run $expected; refusing to replace its schedule."
}

$endBoundary = '2026-12-18T06:05:00'
$weekdayTriggers = @(6, 12, 18 | ForEach-Object {
    $trigger = New-ScheduledTaskTrigger -Weekly `
        -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday `
        -At ((Get-Date).Date.AddHours($_))
    $trigger.EndBoundary = $endBoundary
    $trigger
})
$weekendTrigger = New-ScheduledTaskTrigger -Weekly `
    -DaysOfWeek Saturday,Sunday `
    -At ((Get-Date).Date.AddHours(18))
$weekendTrigger.EndBoundary = $endBoundary
$triggers = @($weekdayTriggers + $weekendTrigger)
Set-ScheduledTask -TaskName $name -Trigger $triggers | Out-Null
$saved = Get-ScheduledTask -TaskName $name
if ($saved.Triggers.Count -ne 4 -or
    @($saved.Triggers | Where-Object { $_.EndBoundary -ne $endBoundary }).Count -ne 0) {
    throw "The $name schedule was not saved with four bounded triggers."
}
$saved.Triggers | Select-Object StartBoundary, EndBoundary, DaysOfWeek
Get-ScheduledTaskInfo -TaskName $name | Select-Object NextRunTime
