# ==============================================================================
# PulseLab — Parser Seguro e Offline de Projetos LEGO SPIKE (.llsp3 / .llsp)
# ==============================================================================
# Extrai métricas agregadas de programação Scratch/Word-blocks para inferência
# de progresso técnico e redução de questionários dos alunos.
#
# PRIVACIDADE E SEGURANÇA:
# - Não extrai strings, comentários ou código bruto.
# - Saída nunca contém texto digitado (entradas, variáveis, listas, mensagens,
#   nomes de projeto/bloco) nem caminhos de arquivo (contêm o usuário Windows).
# - Não persiste nomes, identificadores Bluetooth ou UUID do Hub.
# - Opera 100% offline usando System.IO.Compression nativo do .NET.
# - Compatível com Windows PowerShell 5.1.
# ==============================================================================

Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# Utilitários internos
# ------------------------------------------------------------------------------

# Lê propriedade de PSCustomObject ou dicionário sem falhar (StrictMode-safe).
function Get-SpikeProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return ,$Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return ,$p.Value }
    return $null
}

function Test-SpikeTruthy {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    return ([string]$Value) -match '^(?i)(true|1|sim|yes)$'
}

# Bloco Scratch = objeto com opcode (primitivas soltas são arrays).
function Test-SpikeBlock {
    param($Block)
    if ($null -eq $Block -or $Block -is [System.Array] -or $Block -is [string]) { return $false }
    return $null -ne $Block.PSObject.Properties['opcode']
}

function Test-SpikeShadow {
    param($Block)
    return (Get-SpikeProp $Block "shadow") -eq $true
}

# Opcodes são identificadores fixos do SPIKE; qualquer coisa fora do padrão vira marcador neutro.
function Get-SpikeSafeOpcode {
    param($Block)
    $op = [string](Get-SpikeProp $Block "opcode")
    if ($op -match '^[A-Za-z0-9_\-\.]{1,80}$') { return $op }
    return "_desconhecido"
}

function Get-SpikeSortedNames {
    param($Object)
    if ($null -eq $Object -or $Object -is [System.Array] -or $Object -is [string]) { return ,([string[]]@()) }
    [string[]]$names = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return ,$names
}

# Input Scratch: [tipo, ref, sombra]. Retorna o id se ref aponta para bloco não-sombra.
function Get-SpikeInputBlockId {
    param($Blocks, $InputValue)
    if ($InputValue -isnot [System.Array] -or $InputValue.Count -lt 2) { return $null }
    $ref = $InputValue[1]
    if ($ref -isnot [string] -or -not $Blocks.ContainsKey($ref)) { return $null }
    $child = $Blocks[$ref]
    if ((Test-SpikeBlock $child) -and -not (Test-SpikeShadow $child)) { return $ref }
    return $null
}

function Test-SpikeInvalidDataError {
    param($Exception)
    $e = $Exception
    while ($null -ne $e) {
        if ($e -is [System.IO.InvalidDataException]) { return $true }
        $e = $e.InnerException
    }
    return $false
}

function Read-SpikeZipEntryText {
    param($Archive, [string]$EntryName)
    $entry = $Archive.GetEntry($EntryName)
    if ($null -eq $entry) { return $null }
    $reader = New-Object System.IO.StreamReader -ArgumentList $entry.Open(), ([System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

# scratch.sb3 é um zip dentro do zip: copia para memória e lê project.json.
function Read-SpikeNestedProjectJson {
    param($Archive)
    $entry = $Archive.GetEntry("scratch.sb3")
    if ($null -eq $entry) { return $null }
    $buffer = New-Object System.IO.MemoryStream
    $source = $entry.Open()
    try { $source.CopyTo($buffer) } finally { $source.Dispose() }
    $buffer.Position = 0
    $inner = $null
    try {
        $inner = New-Object System.IO.Compression.ZipArchive -ArgumentList $buffer, ([System.IO.Compression.ZipArchiveMode]::Read)
        return Read-SpikeZipEntryText -Archive $inner -EntryName "project.json"
    } finally {
        if ($inner) { $inner.Dispose() }
        $buffer.Dispose()
    }
}

# ------------------------------------------------------------------------------
# Localização dos projetos
# ------------------------------------------------------------------------------

function Get-SpikeProjectDirectories {
    param([string]$CustomDirectory = "")

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:PULSELAB_SPIKE_DIR) {
        # Override explícito (testes e polos com pasta fora do padrão)
        $candidates.Add([string]$env:PULSELAB_SPIKE_DIR)
        if ($CustomDirectory) { $candidates.Add($CustomDirectory) }
    } else {
        if ($CustomDirectory) { $candidates.Add($CustomDirectory) }
        # Documentos pode estar redirecionado para o OneDrive (inclusive localizado)
        $roots = New-Object System.Collections.Generic.List[string]
        try { $roots.Add([Environment]::GetFolderPath('MyDocuments')) } catch { }
        if ($env:OneDrive) {
            $roots.Add((Join-Path $env:OneDrive "Documents"))
            $roots.Add((Join-Path $env:OneDrive "Documentos"))
        }
        if ($env:USERPROFILE) { $roots.Add((Join-Path $env:USERPROFILE "Documents")) }
        foreach ($root in $roots) {
            if (-not $root) { continue }
            foreach ($sub in @("LEGO SPIKE", "LEGO Education SPIKE")) {
                $candidates.Add((Join-Path $root $sub))
            }
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in $candidates) {
        if (-not $dir) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            $full = [System.IO.Path]::GetFullPath($dir).TrimEnd('\', '/')
        } catch { continue }
        if ($seen.Add($full)) { $full }
    }
}

# Arquivos de projeto, mais recente primeiro. MinLastWriteTime é exclusivo (UTC).
function Get-SpikeProjectFiles {
    param(
        [DateTime]$MinLastWriteTime = [DateTime]::MinValue,
        [string]$CustomDirectory = ""
    )

    $filterAll = $MinLastWriteTime -eq [DateTime]::MinValue
    $minUtc = $MinLastWriteTime
    if ($minUtc.Kind -eq [DateTimeKind]::Local) { $minUtc = $minUtc.ToUniversalTime() }
    $extensions = @(".llsp3", ".llsp", ".spk")

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($dir in @(Get-SpikeProjectDirectories -CustomDirectory $CustomDirectory)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($extensions -notcontains $f.Extension.ToLowerInvariant()) { continue }
            if (-not $filterAll -and $f.LastWriteTimeUtc -le $minUtc) { continue }
            if ($seen.Add($f.FullName)) { $files.Add($f) }
        }
    }
    $files | Sort-Object -Property LastWriteTimeUtc -Descending
}

# Compatibilidade: caminho do projeto mais recente ou $null.
function Find-LatestSpikeProject {
    param(
        [string]$CustomDirectory = "",
        [DateTime]$MinLastWriteTime = [DateTime]::MinValue
    )
    $latest = @(Get-SpikeProjectFiles -MinLastWriteTime $MinLastWriteTime -CustomDirectory $CustomDirectory) | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

# Diagnóstico sem caminhos: só contagens e flags.
function Get-SpikeEnvironmentStatus {
    param([string]$CustomDirectory = "")

    $dirs = @(Get-SpikeProjectDirectories -CustomDirectory $CustomDirectory)
    $files = @(Get-SpikeProjectFiles -CustomDirectory $CustomDirectory)

    $oneDriveDocs = $false
    try {
        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        if ($env:OneDrive -and $myDocs) {
            $od = [System.IO.Path]::GetFullPath($env:OneDrive).TrimEnd('\', '/')
            $md = [System.IO.Path]::GetFullPath($myDocs).TrimEnd('\', '/')
            $cmp = [StringComparison]::OrdinalIgnoreCase
            $oneDriveDocs = $md.Equals($od, $cmp) -or $md.StartsWith($od + '\', $cmp) -or $md.StartsWith($od + '/', $cmp)
        }
    } catch { }

    $newest = $null
    if ($files.Count -gt 0) { $newest = $files[0].LastWriteTimeUtc.ToString("o") }
    $status = "pasta_nao_encontrada"
    if ($dirs.Count -gt 0) { $status = "ok" }

    return [ordered]@{
        status = $status
        directories_found = $dirs.Count
        onedrive_documents = [bool]$oneDriveDocs
        project_count = $files.Count
        newest_project_utc = $newest
    }
}

# ------------------------------------------------------------------------------
# Análise estrutural
# ------------------------------------------------------------------------------

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

# Classificação de um opcode (minúsculo) nas categorias usadas por flags e CT.
function Get-SpikeOpcodeTraits {
    param([string]$OpLower)

    $isFlipper = $OpLower -match '^(flipper|horizontal)'
    $isCore = $OpLower -match '^(control|operator|data|event|procedures|argument|looks|sound|pen|math|text)_'
    $isHat = $OpLower -match '^[a-z]*events?_when'
    $isStartHat = $OpLower -match 'whenprogramstarts$' -or $OpLower -eq "event_whenflagclicked"
    $isBroadcastHat = $OpLower -eq "event_whenbroadcastreceived"
    # Chapéu acionado por sensor/botão do Hub; whenTimer/whenCondition ficam de fora
    $isSensorHat = $isHat -and -not $isStartHat -and -not $isBroadcastHat -and ($OpLower -notmatch 'whentimer$|whencondition$')

    if ($isFlipper) {
        $isMotor = $OpLower -match '^(flipper|horizontal)(more)?(motor|move)_'
        $isSensor = ($OpLower -match '^(flipper|horizontal)(more)?sensors?_') -or $isSensorHat
    } elseif ($isCore) {
        $isMotor = $false
        $isSensor = $isSensorHat
    } else {
        # Extensões legadas (wedo/boost/ev3/motion/sensing)
        $isMotor = $OpLower -match 'motor|motion|move|turn|speed|drive'
        $isSensor = ($OpLower -match 'sensor|sensing_|distance|ultrasonic|color|force|touch|gyro|yaw|pitch|roll|gesture') -or $isSensorHat
    }

    return @{
        hat = $isHat
        start_hat = $isStartHat
        broadcast_hat = $isBroadcastHat
        sensor_hat = $isSensorHat
        motor = [bool]$isMotor
        sensor = [bool]$isSensor
        sensor_read = [bool]($isSensor -and -not $isHat -and $OpLower -notmatch 'reset')
        loop = $OpLower -match '(^|_)(repeat|forever)|^control_while$'
        condition = $OpLower -match '^control_if|wait_until$'
        variable = $OpLower -match '^data_|variable'
        procedure = $OpLower -match '^procedures_'
        motor_param = $OpLower -match '^(flipper|horizontal)(more)?(motor|move)_(motorset|set|movementspeed)'
    }
}

# Serialização canônica de uma pilha: opcodes seguindo next; inputs com blocos
# não-sombra entram recursivamente entre colchetes, em ordem de nome do input.
# Ignora ids, x/y e valores de campo. Em procedures_*, os nomes dos inputs são
# ids de argumento: viram "ARG" e os filhos são ordenados pelo conteúdo.
function Get-SpikeChainSignature {
    param($Blocks, [string]$StartId, $Visited, [int]$Depth = 0)

    $parts = New-Object System.Collections.Generic.List[string]
    $currentId = $StartId
    while ($currentId -and $Blocks.ContainsKey($currentId) -and $Depth -lt 64) {
        if (-not $Visited.Add($currentId)) { break }
        $block = $Blocks[$currentId]
        if (-not (Test-SpikeBlock $block) -or (Test-SpikeShadow $block)) { break }
        $opcode = Get-SpikeSafeOpcode $block
        $isProc = $opcode.StartsWith("procedures_")
        $children = New-Object System.Collections.Generic.List[string]
        $inputs = Get-SpikeProp $block "inputs"
        foreach ($name in (Get-SpikeSortedNames $inputs)) {
            $childId = Get-SpikeInputBlockId -Blocks $Blocks -InputValue (Get-SpikeProp $inputs $name)
            if (-not $childId) { continue }
            $sig = Get-SpikeChainSignature -Blocks $Blocks -StartId $childId -Visited $Visited -Depth ($Depth + 1)
            $label = $name
            if ($isProc) { $label = "ARG" }
            $children.Add($label + "=" + $sig)
        }
        if ($isProc) { $children.Sort([StringComparer]::Ordinal) }
        $piece = $opcode
        if ($children.Count -gt 0) { $piece = $piece + "[" + ($children -join ";") + "]" }
        $parts.Add($piece)
        $next = Get-SpikeProp $block "next"
        $currentId = $null
        if ($next -is [string]) { $currentId = $next }
    }
    return ($parts -join ",")
}

# Chave interna de agrupamento de chapéus (opcode + campos + menus-sombra).
# Usada só para contar pilhas paralelas; nunca sai na saída.
function Get-SpikeHatKey {
    param($Blocks, $Block, [string]$Opcode)
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($Opcode)
    $fields = Get-SpikeProp $Block "fields"
    foreach ($name in (Get-SpikeSortedNames $fields)) {
        $v = Get-SpikeProp $fields $name
        if ($v -is [System.Array] -and $v.Count -gt 0) { $v = $v[0] }
        $parts.Add($name + "=" + [string]$v)
    }
    $inputs = Get-SpikeProp $Block "inputs"
    foreach ($name in (Get-SpikeSortedNames $inputs)) {
        $value = Get-SpikeProp $inputs $name
        if ($value -isnot [System.Array] -or $value.Count -lt 2) { continue }
        $ref = $value[1]
        if ($ref -is [System.Array] -and $ref.Count -gt 1) {
            $parts.Add($name + "=" + [string]$ref[1])
        } elseif ($ref -is [string] -and $Blocks.ContainsKey($ref)) {
            $shadowFields = Get-SpikeProp $Blocks[$ref] "fields"
            foreach ($fname in (Get-SpikeSortedNames $shadowFields)) {
                $fv = Get-SpikeProp $shadowFields $fname
                if ($fv -is [System.Array] -and $fv.Count -gt 0) { $fv = $fv[0] }
                $parts.Add($name + "." + $fname + "=" + [string]$fv)
            }
        }
    }
    return ($parts -join "|")
}

function Get-SpikeSha256Hex {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    } finally {
        $sha.Dispose()
    }
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

# Pensamento computacional: adaptação da rubrica Dr. Scratch
# (Moreno-León, Robles & Román-González, 2015) aos word blocks do SPIKE 3.
# Cada dimensão vai de 0 a 3; vale o maior nível atingido.
#
# | Dimensão            | 1                                   | 2                                          | 3                                                   |
# |---------------------|-------------------------------------|--------------------------------------------|-----------------------------------------------------|
# | flow_control        | pilha com >=2 blocos em sequência   | control_repeat, control_forever            | control_repeat_until, control_while                 |
# | logic               | control_if                          | control_if_else                            | operator_and, operator_or, operator_not             |
# | synchronization     | control_wait                        | event_broadcast, event_whenbroadcastreceived, control_stop | control_wait_until, event_broadcastandwait, chapéu de sensor |
# | parallelism         | 2 pilhas sob o mesmo chapéu de início | 2 pilhas sob o mesmo chapéu de outro evento | >=2 chapéus distintos, cada um com >=2 pilhas      |
# | user_interactivity  | flipperevents_whenProgramStarts     | leitura de sensor (flippersensors_*)        | chapéu de sensor (flipperevents_whenColor/Pressed/Distance/Tilted/Orientation/Gesture/Button...) |
# | data_representation | flippermotor_motorSet*, flippermove_set*/movementSpeed | data_* de variável ou variável em input | data_*list* ou lista em input              |
# | abstraction         | mais de uma pilha                   | procedures_definition                      | definição + procedures_call usado >=2 vezes        |
#
# "Mesmo chapéu" = mesmo opcode e mesmos campos/menus (ex.: mesma cor, mesma mensagem).
# whenTimer e whenCondition não contam como chapéu de sensor.
function Measure-SpikeBlockProgram {
    param($Project)

    $opCounts = New-Object 'System.Collections.Generic.Dictionary[string,int]' -ArgumentList ([StringComparer]::Ordinal)
    $signatures = New-Object System.Collections.Generic.List[string]
    $hatGroups = New-Object 'System.Collections.Generic.Dictionary[string,int]' -ArgumentList ([StringComparer]::Ordinal)
    $hatGroupIsStart = New-Object 'System.Collections.Generic.Dictionary[string,bool]' -ArgumentList ([StringComparer]::Ordinal)

    $totalBlocks = 0
    $executableBlocks = 0
    $topLevelStacks = 0
    $maxChain = 0
    $flags = @{ motor = $false; sensor = $false; loop = $false; condition = $false; variable = $false; procedure = $false }
    $seenTraits = @{ start_hat = $false; sensor_hat = $false; sensor_read = $false; motor_param = $false; list = $false; variable_data = $false }
    $procCalls = 0
    $procDefs = 0

    $targets = Get-SpikeProp $Project "targets"
    foreach ($target in @($targets)) {
        $blocksObj = Get-SpikeProp $target "blocks"
        if ($null -eq $blocksObj -or $blocksObj -is [System.Array] -or $blocksObj -is [string]) { continue }

        $blocks = New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([StringComparer]::Ordinal)
        foreach ($prop in $blocksObj.PSObject.Properties) { $blocks[$prop.Name] = $prop.Value }

        $topIds = New-Object System.Collections.Generic.List[string]
        foreach ($id in @($blocks.Keys)) {
            $block = $blocks[$id]
            if ($block -is [System.Array]) {
                # Primitiva solta: [12, nome, id, x, y] variável; [13, ...] lista
                if ($block.Count -gt 0 -and $block[0] -eq 12) { $seenTraits.variable_data = $true; $flags.variable = $true }
                if ($block.Count -gt 0 -and $block[0] -eq 13) { $seenTraits.list = $true; $flags.variable = $true }
                continue
            }
            if (-not (Test-SpikeBlock $block)) { continue }
            $totalBlocks++
            if (Test-SpikeShadow $block) { continue }
            $executableBlocks++

            $opcode = Get-SpikeSafeOpcode $block
            if ($opCounts.ContainsKey($opcode)) { $opCounts[$opcode] = $opCounts[$opcode] + 1 } else { $opCounts[$opcode] = 1 }
            $opLower = $opcode.ToLowerInvariant()
            $traits = Get-SpikeOpcodeTraits $opLower

            if ($traits.motor) { $flags.motor = $true }
            if ($traits.sensor) { $flags.sensor = $true }
            if ($traits.loop) { $flags.loop = $true }
            if ($traits.condition) { $flags.condition = $true }
            if ($traits.variable) { $flags.variable = $true }
            if ($traits.procedure) { $flags.procedure = $true }
            if ($traits.start_hat) { $seenTraits.start_hat = $true }
            if ($traits.sensor_hat) { $seenTraits.sensor_hat = $true }
            if ($traits.sensor_read) { $seenTraits.sensor_read = $true }
            if ($traits.motor_param) { $seenTraits.motor_param = $true }
            if ($opLower -match '^data_.*list') { $seenTraits.list = $true }
            elseif ($opLower -match '^data_.*variable') { $seenTraits.variable_data = $true }
            if ($opLower -eq "procedures_call") { $procCalls++ }
            if ($opLower -eq "procedures_definition") { $procDefs++ }

            # Variáveis e listas soltas dentro de inputs
            $inputs = Get-SpikeProp $block "inputs"
            foreach ($name in (Get-SpikeSortedNames $inputs)) {
                $value = Get-SpikeProp $inputs $name
                if ($value -isnot [System.Array]) { continue }
                foreach ($item in $value) {
                    if ($item -is [System.Array] -and $item.Count -gt 0) {
                        if ($item[0] -eq 12) { $seenTraits.variable_data = $true; $flags.variable = $true }
                        if ($item[0] -eq 13) { $seenTraits.list = $true; $flags.variable = $true }
                    }
                }
            }

            if ((Get-SpikeProp $block "topLevel") -eq $true) { $topIds.Add($id) }
        }

        $visited = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::Ordinal)
        foreach ($topId in $topIds) {
            $topLevelStacks++
            $block = $blocks[$topId]

            # Comprimento da sequência principal
            $length = 0
            $cursor = $topId
            $guard = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::Ordinal)
            while ($cursor -and $blocks.ContainsKey($cursor) -and $guard.Add($cursor) -and (Test-SpikeBlock $blocks[$cursor])) {
                $length++
                $next = Get-SpikeProp $blocks[$cursor] "next"
                $cursor = $null
                if ($next -is [string]) { $cursor = $next }
            }
            if ($length -gt $maxChain) { $maxChain = $length }

            $opcode = Get-SpikeSafeOpcode $block
            $traits = Get-SpikeOpcodeTraits $opcode.ToLowerInvariant()
            if ($traits.hat) {
                $key = Get-SpikeHatKey -Blocks $blocks -Block $block -Opcode $opcode
                if ($hatGroups.ContainsKey($key)) { $hatGroups[$key] = $hatGroups[$key] + 1 } else { $hatGroups[$key] = 1 }
                $hatGroupIsStart[$key] = [bool]$traits.start_hat
            }

            $signatures.Add((Get-SpikeChainSignature -Blocks $blocks -StartId $topId -Visited $visited))
        }
    }

    $has = { param([string[]]$Ops) foreach ($o in $Ops) { if ($opCounts.ContainsKey($o)) { return $true } }; return $false }

    # flow_control
    $flow = 0
    if (& $has @("control_repeat_until", "control_while")) { $flow = 3 }
    elseif ($flags.loop) { $flow = 2 }
    elseif ($maxChain -ge 2) { $flow = 1 }

    # logic
    $logic = 0
    if (& $has @("operator_and", "operator_or", "operator_not")) { $logic = 3 }
    elseif (& $has @("control_if_else")) { $logic = 2 }
    elseif (& $has @("control_if")) { $logic = 1 }

    # synchronization
    $sync = 0
    if ((& $has @("control_wait_until", "event_broadcastandwait")) -or $seenTraits.sensor_hat) { $sync = 3 }
    elseif (& $has @("event_broadcast", "event_whenbroadcastreceived", "control_stop")) { $sync = 2 }
    elseif (& $has @("control_wait")) { $sync = 1 }

    # parallelism
    $parallel = 0
    $multiGroups = 0
    $multiStart = $false
    $multiOther = $false
    foreach ($key in $hatGroups.Keys) {
        if ($hatGroups[$key] -ge 2) {
            $multiGroups++
            if ($hatGroupIsStart[$key]) { $multiStart = $true } else { $multiOther = $true }
        }
    }
    if ($multiGroups -ge 2) { $parallel = 3 }
    elseif ($multiOther) { $parallel = 2 }
    elseif ($multiStart) { $parallel = 1 }

    # user_interactivity
    $ui = 0
    if ($seenTraits.sensor_hat) { $ui = 3 }
    elseif ($seenTraits.sensor_read) { $ui = 2 }
    elseif ($seenTraits.start_hat) { $ui = 1 }

    # data_representation
    $data = 0
    if ($seenTraits.list) { $data = 3 }
    elseif ($seenTraits.variable_data) { $data = 2 }
    elseif ($seenTraits.motor_param) { $data = 1 }

    # abstraction
    $abstraction = 0
    if ($procDefs -gt 0 -and $procCalls -ge 2) { $abstraction = 3 }
    elseif ($procDefs -gt 0) { $abstraction = 2 }
    elseif ($topLevelStacks -gt 1) { $abstraction = 1 }

    $ct = [ordered]@{
        flow_control = $flow
        logic = $logic
        synchronization = $sync
        parallelism = $parallel
        user_interactivity = $ui
        data_representation = $data
        abstraction = $abstraction
        total = $flow + $logic + $sync + $parallel + $ui + $data + $abstraction
    }

    [string[]]$opNames = @($opCounts.Keys)
    [Array]::Sort($opNames, [StringComparer]::Ordinal)
    $countsOut = [ordered]@{}
    foreach ($op in $opNames) { $countsOut[$op] = $opCounts[$op] }

    $structureHash = $null
    if ($signatures.Count -gt 0) {
        [string[]]$sigArray = $signatures.ToArray()
        [Array]::Sort($sigArray, [StringComparer]::Ordinal)
        $structureHash = Get-SpikeSha256Hex ($sigArray -join "`n")
    }

    return @{
        total_blocks = $totalBlocks
        executable_blocks = $executableBlocks
        top_level_stacks = $topLevelStacks
        uses_motor = $flags.motor
        uses_sensor = $flags.sensor
        uses_loop = $flags.loop
        uses_condition = $flags.condition
        uses_variable = $flags.variable
        uses_procedure = $flags.procedure
        opcode_counts = $countsOut
        structure_hash = $structureHash
        ct_score = $ct
    }
}

function New-SpikeMetricsResult {
    param(
        [string]$Status,
        [bool]$Saved = $false,
        [string]$Format = "unknown",
        [string]$Language = "unknown",
        [string]$ErrorCode = "",
        $ModifiedUtc = $null
    )
    $result = [ordered]@{
        source = "spike_project"
        spike_status = $Status
        project_saved = $Saved
        format = $Format
        language = $Language
        total_blocks = 0
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
        opcode_counts = [ordered]@{}
        structure_hash = $null
        ct_score = $null
        ct_score_version = "drscratch-adaptado-spike-v0"
        project_modified_utc = $ModifiedUtc
        timestamp = [DateTime]::UtcNow.ToString("o")
    }
    if ($ErrorCode) { $result.error = $ErrorCode }
    return $result
}

# Nunca lança exceção. spike_status: ok | python | arquivo_bloqueado | arquivo_invalido | sem_projeto
function Get-SpikeProjectMetrics {
    param(
        [string]$ProjectPath = "",
        [psobject]$PreviousMetrics = $null,
        [DateTime]$MinLastWriteTime = [DateTime]::MinValue
    )

    $targetFile = $null
    try {
        if ($ProjectPath -and (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
            $targetFile = $ProjectPath
        } elseif (-not $ProjectPath) {
            $targetFile = Find-LatestSpikeProject -MinLastWriteTime $MinLastWriteTime
        }
    } catch { $targetFile = $null }

    if (-not $targetFile) {
        return [PSCustomObject](New-SpikeMetricsResult -Status "sem_projeto" -ErrorCode "project_not_found")
    }

    $format = "unknown"
    $modifiedUtc = $null
    try {
        $item = Get-Item -LiteralPath $targetFile -ErrorAction Stop
        $ext = $item.Extension.TrimStart('.').ToLowerInvariant()
        if ($ext -match '^(llsp3|llsp|spk)$') { $format = $ext }
        $modifiedUtc = $item.LastWriteTimeUtc.ToString("o")
    } catch { }

    # Leitura com retry para o caso de o SPIKE estar salvando o arquivo no mesmo instante
    $fileStream = $null
    $zipArchive = $null
    $openFailure = "arquivo_bloqueado"
    $share = [System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    for ($attempt = 0; $attempt -lt 3 -and $null -eq $zipArchive; $attempt++) {
        try {
            $fileStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            $zipArchive = New-Object System.IO.Compression.ZipArchive -ArgumentList $fileStream, ([System.IO.Compression.ZipArchiveMode]::Read)
        } catch {
            # ZipArchive inválido não fecha o stream: descarta aqui para não vazar handle
            if ($fileStream) { $fileStream.Dispose(); $fileStream = $null }
            $zipArchive = $null
            $openFailure = "arquivo_bloqueado"
            if (Test-SpikeInvalidDataError $_.Exception) { $openFailure = "arquivo_invalido" }
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 200 }
        }
    }

    if ($null -eq $zipArchive) {
        $code = "file_locked"
        if ($openFailure -eq "arquivo_invalido") { $code = "invalid_project" }
        return [PSCustomObject](New-SpikeMetricsResult -Status $openFailure -Format $format -ErrorCode $code -ModifiedUtc $modifiedUtc)
    }

    try {
        # 1. Linguagem pelo manifest.json (só o tipo; o nome do projeto é ignorado)
        $language = "word-blocks"
        $hasManifestType = $false
        try {
            $manifestText = Read-SpikeZipEntryText -Archive $zipArchive -EntryName "manifest.json"
            if ($manifestText) {
                $manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
                $type = [string](Get-SpikeProp $manifest "type")
                if ($type) {
                    $type = $type.ToLowerInvariant()
                    if ($type -match '^[a-z0-9\-]{1,32}$') { $language = $type; $hasManifestType = $true }
                }
            }
        } catch { }

        $isPython = $language -eq "python"
        if (-not $isPython -and -not $hasManifestType -and $null -eq $zipArchive.GetEntry("scratch.sb3") -and $null -eq $zipArchive.GetEntry("project.json") -and $null -ne $zipArchive.GetEntry("projectbody.json")) {
            $isPython = $true
        }
        if ($isPython) {
            $result = New-SpikeMetricsResult -Status "python" -Saved $true -Format $format -Language "python" -ModifiedUtc $modifiedUtc
            $result.inferred_stage = "not_applicable"
            $result.inference_confidence = 0.0
            return [PSCustomObject]$result
        }

        # 2. scratch.sb3 (zip interno) ou project.json direto
        $projectJsonContent = $null
        try {
            if ($null -ne $zipArchive.GetEntry("scratch.sb3")) {
                $projectJsonContent = Read-SpikeNestedProjectJson -Archive $zipArchive
            } else {
                $projectJsonContent = Read-SpikeZipEntryText -Archive $zipArchive -EntryName "project.json"
            }
        } catch {
            $projectJsonContent = $null
        }

        $projectObj = $null
        if ($projectJsonContent) {
            try { $projectObj = $projectJsonContent | ConvertFrom-Json -ErrorAction Stop } catch { $projectObj = $null }
        }
        if ($null -eq $projectObj -or $null -eq (Get-SpikeProp $projectObj "targets")) {
            return [PSCustomObject](New-SpikeMetricsResult -Status "arquivo_invalido" -Format $format -Language $language -ErrorCode "invalid_project" -ModifiedUtc $modifiedUtc)
        }

        $analysis = Measure-SpikeBlockProgram -Project $projectObj

        $blocksAdded = 0
        $blocksRemoved = 0
        $prevBlocks = Get-SpikeProp $PreviousMetrics "executable_blocks"
        if ($null -ne $prevBlocks) {
            $delta = $analysis.executable_blocks - [int]$prevBlocks
            if ($delta -gt 0) { $blocksAdded = $delta }
            if ($delta -lt 0) { $blocksRemoved = [Math]::Abs($delta) }
        }

        $stageResult = Infer-SpikeStage -ExecutableBlocks $analysis.executable_blocks `
            -UsesMotor $analysis.uses_motor `
            -UsesSensor $analysis.uses_sensor `
            -UsesLoop $analysis.uses_loop `
            -UsesCondition $analysis.uses_condition

        $result = New-SpikeMetricsResult -Status "ok" -Saved $true -Format $format -Language $language -ModifiedUtc $modifiedUtc
        foreach ($key in @("total_blocks", "executable_blocks", "top_level_stacks", "uses_motor", "uses_sensor", "uses_loop", "uses_condition", "uses_variable", "uses_procedure", "opcode_counts", "structure_hash", "ct_score")) {
            $result[$key] = $analysis[$key]
        }
        $result.blocks_added_since_previous = $blocksAdded
        $result.blocks_removed_since_previous = $blocksRemoved
        $result.inferred_stage = $stageResult.stage
        $result.inference_confidence = $stageResult.confidence
        return [PSCustomObject]$result
    } catch {
        return [PSCustomObject](New-SpikeMetricsResult -Status "arquivo_invalido" -Format $format -ErrorCode "invalid_project" -ModifiedUtc $modifiedUtc)
    } finally {
        if ($zipArchive) { $zipArchive.Dispose() }
        if ($fileStream) { $fileStream.Dispose() }
    }
}

# ------------------------------------------------------------------------------
# Missões do dia
# ------------------------------------------------------------------------------

# Normaliza critérios (chaves em inglês ou português) para o formato de
# Measure-SpikeMissionCoverage. Aceita também lista de nomes ("uses_motor", "opcode:x").
function ConvertTo-SpikeMissionCriteria {
    param($Raw)

    $criteria = [ordered]@{
        uses_motor = $false
        uses_sensor = $false
        uses_loop = $false
        uses_condition = $false
        min_executable_blocks = 0
        required_opcodes = [string[]]@()
    }
    if ($null -eq $Raw) { return $criteria }

    $aliases = [ordered]@{
        uses_motor = @("uses_motor", "usa_motor", "motor")
        uses_sensor = @("uses_sensor", "usa_sensor", "sensor")
        uses_loop = @("uses_loop", "usa_laco", "usa_repeticao", "laco", "repeticao")
        uses_condition = @("uses_condition", "usa_condicao", "condicao")
        min_executable_blocks = @("min_executable_blocks", "min_blocos_executaveis", "min_blocos", "blocos_minimos")
        required_opcodes = @("required_opcodes", "opcodes_obrigatorios", "opcodes")
    }
    $opcodes = New-Object System.Collections.Generic.List[string]

    if ($Raw -is [System.Array]) {
        foreach ($item in $Raw) {
            $s = [string]$item
            if ($s -match '^opcode:(.+)$') { $opcodes.Add($Matches[1]) }
            elseif (@("uses_motor", "uses_sensor", "uses_loop", "uses_condition") -contains $s) { $criteria[$s] = $true }
        }
    } else {
        foreach ($key in @("uses_motor", "uses_sensor", "uses_loop", "uses_condition")) {
            foreach ($alias in $aliases[$key]) {
                if (Test-SpikeTruthy (Get-SpikeProp $Raw $alias)) { $criteria[$key] = $true }
            }
        }
        foreach ($alias in $aliases.min_executable_blocks) {
            $v = Get-SpikeProp $Raw $alias
            $n = 0
            if ($null -ne $v -and [int]::TryParse([string]$v, [ref]$n) -and $n -gt 0) { $criteria.min_executable_blocks = $n; break }
        }
        foreach ($alias in $aliases.required_opcodes) {
            $v = Get-SpikeProp $Raw $alias
            if ($null -ne $v) { foreach ($op in @($v)) { $opcodes.Add([string]$op) } }
        }
    }

    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($op in $opcodes) {
        if ($op -match '^[A-Za-z0-9_\-\.]{1,80}$' -and -not $clean.Contains($op)) { $clean.Add($op) }
    }
    $criteria.required_opcodes = [string[]]$clean.ToArray()
    return $criteria
}

function Measure-SpikeMissionCoverage {
    param($Metrics, $Mission)

    $raw = Get-SpikeProp $Mission "criteria"
    if ($null -eq $raw) { $raw = Get-SpikeProp $Mission "criterios" }
    $criteria = ConvertTo-SpikeMissionCriteria $raw

    $total = 0
    $met = 0
    $missing = New-Object System.Collections.Generic.List[string]

    foreach ($flag in @("uses_motor", "uses_sensor", "uses_loop", "uses_condition")) {
        if (-not $criteria[$flag]) { continue }
        $total++
        if ((Get-SpikeProp $Metrics $flag) -eq $true) { $met++ } else { $missing.Add($flag) }
    }

    if ($criteria.min_executable_blocks -gt 0) {
        $total++
        $blocks = 0
        [void][int]::TryParse([string](Get-SpikeProp $Metrics "executable_blocks"), [ref]$blocks)
        if ($blocks -ge $criteria.min_executable_blocks) { $met++ } else { $missing.Add("min_executable_blocks") }
    }

    $counts = Get-SpikeProp $Metrics "opcode_counts"
    foreach ($op in $criteria.required_opcodes) {
        $total++
        $n = 0
        [void][int]::TryParse([string](Get-SpikeProp $counts $op), [ref]$n)
        if ($n -gt 0) { $met++ } else { $missing.Add("opcode:" + $op) }
    }

    $coverage = $null
    if ($total -gt 0) { $coverage = [Math]::Round($met / $total, 2) }

    return [ordered]@{
        mission_id = [string](Get-SpikeProp $Mission "mission_id")
        criteria_total = $total
        criteria_met = $met
        coverage = $coverage
        missing = [string[]]$missing.ToArray()
    }
}

# Missão do calendário para a data local (yyyy-MM-dd) ou $null.
function Resolve-SpikeMission {
    param(
        $Catalog,
        $Calendar,
        [DateTime]$Date = (Get-Date)
    )

    $local = $Date
    if ($local.Kind -eq [DateTimeKind]::Utc) { $local = $local.ToLocalTime() }
    $dayKey = $local.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)

    $entries = $Calendar
    if ($null -ne $Calendar -and $Calendar -isnot [System.Array]) {
        foreach ($wrapper in @("calendario", "calendar", "entradas")) {
            $inner = Get-SpikeProp $Calendar $wrapper
            if ($null -ne $inner) { $entries = $inner; break }
        }
    }

    $missionId = $null
    foreach ($entry in @($entries)) {
        $day = Get-SpikeProp $entry "data"
        if ($day -is [DateTime]) { $day = $day.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture) }
        if ([string]$day -eq $dayKey) {
            $missionId = [string](Get-SpikeProp $entry "mission_id")
            break
        }
    }
    if (-not $missionId) { return $null }

    $missions = Get-SpikeProp $Catalog "missoes"
    if ($null -eq $missions -and $Catalog -is [System.Array]) { $missions = $Catalog }
    foreach ($mission in @($missions)) {
        if ([string](Get-SpikeProp $mission "mission_id") -ne $missionId) { continue }
        $raw = Get-SpikeProp $mission "criterios"
        if ($null -eq $raw) { $raw = Get-SpikeProp $mission "criteria" }
        return [ordered]@{
            mission_id = $missionId
            titulo = Get-SpikeProp $mission "titulo"
            data = $dayKey
            criteria = ConvertTo-SpikeMissionCriteria $raw
        }
    }
    return $null
}
