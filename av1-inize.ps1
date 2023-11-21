# Set the terminal window title
$Host.UI.RawUI.WindowTitle = "AV1-inizer"

# Reset the Windows Terminal progress bar to 'none' at the start
$esc = [char]27
[Console]::Write("$esc]9;4;0$esc\")

# Display script title and version
Write-Host "AV1-inizer v1.0 by cryptofyre" -ForegroundColor Cyan

# Detect available GPUs/Display Adapters
$gpus = Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty Name
Write-Host "Detected GPUs/Display Adapters:"
$gpus | foreach { 
    if ($_ -match "NVIDIA") { Write-Host "- $_" -ForegroundColor Green }
    elseif ($_ -match "AMD") { Write-Host "- $_" -ForegroundColor Red }
    elseif ($_ -match "Intel") { Write-Host "- $_" -ForegroundColor Blue }
    else { Write-Host "- $_" }
}

# Determine available encoder options based on detected GPUs
$encoderOptions = @("CPU (libaom-av1)")
if ($gpus -match "NVIDIA") { $encoderOptions += "NVIDIA NVENC (AV1)" }
if ($gpus -match "AMD") { $encoderOptions += "AMD AV1 Encoder (amf_av1)" }
if ($gpus -match "Intel") { $encoderOptions += "Intel AV1 Encoder (av1_qsv)" }

# Display encoder options with color coding
Write-Host "Select the encoder for AV1 encoding:"
$encoderOptions | foreach {
    $index = $encoderOptions.IndexOf($_)
    if ($_ -match "NVIDIA") { Write-Host "$index. $_" -ForegroundColor Green }
    elseif ($_ -match "AMD") { Write-Host "$index. $_" -ForegroundColor Red }
    elseif ($_ -match "Intel") { Write-Host "$index. $_" -ForegroundColor Blue }
    else { Write-Host "$index. $_" }
}
$selectedEncoderIndex = Read-Host "Enter the number of the encoder"

# Check if the selected index is valid
if (-not ($selectedEncoderIndex -ge 0 -and $selectedEncoderIndex -lt $encoderOptions.Length)) {
    Write-Host "Invalid selection. Please rerun the script and enter a valid number."
    exit
}

# Prompt the user for the source directory
$sourceDir = Read-Host "Please enter the path to the video files"

# Validate the input and exit if the path is not valid
if (-not (Test-Path -Path $sourceDir)) {
    Write-Host "The path you entered does not exist. Please rerun the script and enter a valid path."
    exit
}

$destDir = "${sourceDir}\converted"

# Create the destination directory if it doesn't exist
if (-not (Test-Path -Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir
}

# Get all files in the source directory and then filter for video files
$allFiles = Get-ChildItem -Path $sourceDir -File
$videoFiles = $allFiles | Where-Object { $_.Extension -match "^\.(mov|MOV|mp4|MP4|mkv|MKV|webm|WEBM)$" }

# Total number of files
$totalFiles = $videoFiles.Count
$fileCounter = 0

# Check if there are video files in the directory
if ($totalFiles -eq 0) {
    Write-Host "No video files found in the specified directory."
    exit
}

# Clear the terminal after initial configuration
Clear-Host

# Display script title and version
Write-Host "AV1-inizer v1.0 by cryptofyre" -ForegroundColor Cyan

# Loop through each video file and convert it
foreach ($file in $videoFiles) {
    $fileCounter++
    $originalFileSize = (Get-Item $file.FullName).Length
    $destFile = "${destDir}\$($file.BaseName)_AV1.mkv"
	$skipFile = $false
	
	# Update the progress bar with current job information
    $progressMessage = "Encoding file ($fileCounter of $totalFiles): $($file.Name)"
    $progress = ($fileCounter / $totalFiles) * 100
    Write-Progress -Activity "Converting Videos" -Status $progressMessage -PercentComplete $progress -Id 1
    [Console]::Write("$esc]9;4;1;$([Math]::Round($progress))$esc\")

    # Show current job
    Write-Host "Encoding file: $($file.Name)" -ForegroundColor Green

    # Select encoder based on user choice
    switch ($selectedEncoderIndex) {
        0 { $encoder = "libaom-av1" }
        1 { $encoder = "av1_nvenc" }
        2 { $encoder = "amf_av1" } # AMD AV1 Encoder
        3 { $encoder = "av1_qsv" } # Intel AV1 Encoder
        default { Write-Host "Invalid encoder selection."; exit }
    }

    try {
        # Attempt AV1 encoding with GPU and error handling
        ffmpeg -i "$($file.FullName)" -c:v $encoder -preset p7 -rc constqp -qp 15 -c:a copy -c:s copy "$destFile" 2>$null

        if ($LastExitCode -ne 0) { throw }
    } catch {
        # Clean up any failed encoding output
        if (Test-Path $destFile) { Remove-Item $destFile }

        Write-Host "Warning: GPU encoding failed for file: $($file.Name)" -ForegroundColor Yellow
        $userChoice = $host.ui.PromptForChoice("Choose an Action", "GPU encoding failed. What would you like to do?", 
                    @("&Fallback to CPU Encoding (This could take a long time.)", "&Skip File", "&Exit Script"), 0)
					

        switch ($userChoice) {
            0 { 
                Write-Host "Falling back to CPU encoding (libaom-av1)." -ForegroundColor Yellow
                ffmpeg -i "$($file.FullName)" -c:v libaom-av1 -crf 30 -b:v 0 -c:a copy -c:s copy "$destFile"
            }
            1 {
                Write-Host "Skipping file: $($file.Name)" -ForegroundColor Yellow
				continue
            }
            2 {
                Write-Host "Exiting script." -ForegroundColor Red
                exit
            }
        }
    }
	
    # Compare file sizes and move the original file if the re-encoded file is larger
    if (Test-Path $destFile) {
        $convertedFileSize = (Get-Item $destFile).Length
        if ($convertedFileSize -gt $originalFileSize) {
            Move-Item -Path $file.FullName -Destination $destFile -Force
        }
    } else {
		if ($LastExitCode -ne 0 -and $userChoice -ne 1) {
          Write-Host "Failed to convert file: $($file.Name)" -ForegroundColor Red
		}
    }
}

# Reset the Windows Terminal progress bar to 'none' after completion
[Console]::Write("$esc]9;4;0$esc\")

Write-Host "Conversion completed."
