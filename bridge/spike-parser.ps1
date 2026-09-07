# ==============================================================================
# PulseLab — Parser Seguro e Offline de Projetos LEGO SPIKE (.llsp3 / .llsp)
# ==============================================================================
# Extrai métricas agregadas de programação Scratch/Word-blocks para inferência
# de progresso técnico e redução de questionários dos alunos.
#
# PRIVACIDADE E SEGURANÇA:
# - Não extrai strings, comentários ou código bruto.
# - Não persiste nomes, identificadores Bluetooth ou UUID do Hub.
# - Opera 100% offline usando System.IO.Compression nativo do .NET.
# ==============================================================================

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

function Find-LatestSpikeProject {
    param(
        [string]$CustomDirectory = ""
    )

    $searchDir = if ($CustomDirectory -and (Test-Path $CustomDirectory)) {
        $CustomDirectory
    } else {
        Join-Path $env:USERPROFILE "Documents\LEGO SPIKE"
    }

    if (-not (Test-Path $searchDir)) {
        return $null
    }

    $candidates = Get-ChildItem -Path $searchDir -Include "*.llsp3", "*.llsp", "*.spk" -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($candidates -and $candidates.Count -gt 0) {
        return $candidates[0].FullName
    }

    return $null
}

function Infer-SpikeStage {
    param(
        [int]$ExecutableBlocks,
        [bool]$UsesMotor,
        [bool]$UsesSensor,
        [bool]$UsesLoop,
        [bool]$UsesCondition
    )

    if ($ExecutableBlocks -le 0) {
        return @{ stage = "empty"; confidence = 0.99 }
    }

    if ($UsesMotor -and $UsesSensor -and ($UsesLoop -or $UsesCondition)) {
        return @{ stage = "integrated_mission"; confidence = 0.92 }
    }

    if ($UsesMotor -and $UsesLoop) {
        return @{ stage = "autonomous_loop"; confidence = 0.88 }
    }

    if ($UsesMotor -and $UsesSensor) {
        return @{ stage = "sensor_reactive"; confidence = 0.85 }
    }

    if ($UsesMotor) {
        return @{ stage = "basic_movement"; confidence = 0.85 }
    }

    if ($ExecutableBlocks -gt 0 -and -not $UsesMotor -and -not $UsesSensor) {
        return @{ stage = "initial_setup"; confidence = 0.80 }
    }

    return @{ stage = "exploring"; confidence = 0.70 }
}

function Get-SpikeProjectMetrics {
    param(
        [string]$ProjectPath = "",
        [psobject]$PreviousMetrics = $null
    )

    $targetFile = if ($ProjectPath -and (Test-Path $ProjectPath)) {
        $ProjectPath
    } else {
        Find-LatestSpikeProject
    }

    if (-not $targetFile -or -not (Test-Path $targetFile)) {
        return [PSCustomObject]@{
            source = "spike_project"
            project_saved = $false
            format = "unknown"
            executable_blocks = 0
            top_level_stacks = 0
            uses_motor = $false
            uses_sensor = $false
            uses_loop = $false
            uses_condition = $false
            uses_variable = $false
            uses_procedure = $false
            blocks_added_since_previous = 0
            blocks_removed_since_previous = 0
            inferred_stage = "empty"
            inference_confidence = 0.99
            error = "project_not_found"
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }

    # Leitura com retry para o caso de o SPIKE estar salvando o arquivo no mesmo instante
    $retryCount = 0
    $zipArchive = $null
    while ($retryCount -lt 3 -and $null -eq $zipArchive) {
        try {
            $fileStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $zipArchive = New-Object System.IO.Compression.ZipArchive($fileStream, [System.IO.Compression.ZipArchiveMode]::Read)
        } catch {
            $retryCount++
            Start-Sleep -Milliseconds 200
        }
    }

    if ($null -eq $zipArchive) {
        return [PSCustomObject]@{
            source = "spike_project"
            project_saved = $false
            format = "unknown"
            executable_blocks = 0
            top_level_stacks = 0
            uses_motor = $false
            uses_sensor = $false
            uses_loop = $false
            uses_condition = $false
            uses_variable = $false
            uses_procedure = $false
            blocks_added_since_previous = 0
            blocks_removed_since_previous = 0
            inferred_stage = "empty"
            inference_confidence = 0.99
            error = "file_locked_or_corrupt"
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }

    try {
        $projectJsonContent = $null
        $language = "word-blocks"

        # 1. Checar manifest.json se existir
        $manifestEntry = $zipArchive.GetEntry("manifest.json")
        if ($manifestEntry) {
            $mReader = New-Object System.IO.StreamReader($manifestEntry.Open(), [System.Text.Encoding]::UTF8)
            $mJson = $mReader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
            $mReader.Close()
            if ($mJson -and $mJson.type) {
                $language = [string]$mJson.type
            }
        }

        # 2. Localizar scratch.sb3 ou project.json direto
        $sb3Entry = $zipArchive.GetEntry("scratch.sb3")
        if ($sb3Entry) {
            $sb3Stream = $sb3Entry.Open()
            $innerZip = New-Object System.IO.Compression.ZipArchive($sb3Stream, [System.IO.Compression.ZipArchiveMode]::Read)
            $innerProj = $innerZip.GetEntry("project.json")
            if ($innerProj) {
                $pReader = New-Object System.IO.StreamReader($innerProj.Open(), [System.Text.Encoding]::UTF8)
                $projectJsonContent = $pReader.ReadToEnd()
                $pReader.Close()
            }
            $innerZip.Dispose()
            $sb3Stream.Close()
        } else {
            $directProj = $zipArchive.GetEntry("project.json")
            if ($directProj) {
                $pReader = New-Object System.IO.StreamReader($directProj.Open(), [System.Text.Encoding]::UTF8)
                $projectJsonContent = $pReader.ReadToEnd()
                $pReader.Close()
            }
        }

        if (-not $projectJsonContent) {
            return [PSCustomObject]@{
                source = "spike_project"
                project_saved = $true
                format = "llsp3"
                language = $language
                executable_blocks = 0
                top_level_stacks = 0
                uses_motor = $false
                uses_sensor = $false
                uses_loop = $false
                uses_condition = $false
                uses_variable = $false
                uses_procedure = $false
                blocks_added_since_previous = 0
                blocks_removed_since_previous = 0
                inferred_stage = "initial_setup"
                inference_confidence = 0.70
                timestamp = [DateTime]::UtcNow.ToString("o")
            }
        }

        $projectObj = $projectJsonContent | ConvertFrom-Json

        $totalBlocks = 0
        $executableBlocks = 0
        $topLevelStacks = 0
        $usesMotor = $false
        $usesSensor = $false
        $usesLoop = $false
        $usesCondition = $false
        $usesVariable = $false
        $usesProcedure = $false

        if ($projectObj.targets) {
            foreach ($target in $projectObj.targets) {
                if ($target.blocks) {
                    $blockProps = $target.blocks.PSObject.Properties
                    foreach ($prop in $blockProps) {
                        $blockData = $prop.Value
                        if ($blockData -is [PSCustomObject]) {
                            $totalBlocks++

                            $isShadow = ($blockData.PSObject.Properties.Name -contains "shadow") -and ($blockData.shadow -eq $true)
                            $isTop = ($blockData.PSObject.Properties.Name -contains "topLevel") -and ($blockData.topLevel -eq $true)

                            if (-not $isShadow) {
                                $executableBlocks++
                            }
                            if ($isTop) {
                                $topLevelStacks++
                            }

                            $opcode = if ($blockData.PSObject.Properties.Name -contains "opcode") { [string]$blockData.opcode } else { "" }
                            $opLower = $opcode.ToLowerInvariant()

                            # Categorização de Opcodes
                            if ($opLower -match "motor|motion|move|turn|speed|drive") { $usesMotor = $true }
                            if ($opLower -match "sensor|distance|ultrasonic|color|force|touch|gyro|yaw|pitch|roll|gesture") { $usesSensor = $true }
                            if ($opLower -match "repeat|forever|while|until") { $usesLoop = $true }
                            if ($opLower -match "control_if|wait_until") { $usesCondition = $true }
                            if ($opLower -match "data_|variable") { $usesVariable = $true }
                            if ($opLower -match "procedures_|custom_block") { $usesProcedure = $true }
                        }
                    }
                }
            }
        }

        $blocksAdded = 0
        $blocksRemoved = 0
        if ($PreviousMetrics -and ($PreviousMetrics.PSObject.Properties.Name -contains "executable_blocks")) {
            $prevBlocks = [int]$PreviousMetrics.executable_blocks
            $delta = $executableBlocks - $prevBlocks
            if ($delta -gt 0) { $blocksAdded = $delta }
            if ($delta -lt 0) { $blocksRemoved = [Math]::Abs($delta) }
        }

        $stageResult = Infer-SpikeStage -ExecutableBlocks $executableBlocks `
            -UsesMotor $usesMotor `
            -UsesSensor $usesSensor `
            -UsesLoop $usesLoop `
            -UsesCondition $usesCondition

        return [PSCustomObject]@{
            source = "spike_project"
            project_saved = $true
            format = "llsp3"
            language = $language
            total_blocks = $totalBlocks
            executable_blocks = $executableBlocks
            top_level_stacks = $topLevelStacks
            uses_motor = $usesMotor
            uses_sensor = $usesSensor
            uses_loop = $usesLoop
            uses_condition = $usesCondition
            uses_variable = $usesVariable
            uses_procedure = $usesProcedure
            blocks_added_since_previous = $blocksAdded
            blocks_removed_since_previous = $blocksRemoved
            inferred_stage = $stageResult.stage
            inference_confidence = $stageResult.confidence
            timestamp = [DateTime]::UtcNow.ToString("o")
        }
    }
    finally {
        if ($zipArchive) { $zipArchive.Dispose() }
        if ($fileStream) { $fileStream.Close(); $fileStream.Dispose() }
    }
}
