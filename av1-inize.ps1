# Set the terminal window title
$Host.UI.RawUI.WindowTitle = "AV1-inizer"

# Reset the Windows Terminal progress bar to 'none' at the start
$esc = [char]27
[Console]::Write("$esc]9;4;0$esc\")

$version = "1.1"

# Display script title and version
Write-Host "AV1-inizer v$($version) by cryptofyre" -ForegroundColor Cyan

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
if ($gpus -match "NVIDIA") { $encoderOptions += "NVIDIA NVENC (av1_nvenc)" }
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
    [void](New-Item -ItemType Directory -Path $destDir)
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

# Prompt user if they would like to use their own RF values, or allow the script to automatically determine.
$userChoiceRF = $host.ui.PromptForChoice("RF Value Selection", "Choose how you want to set the RF value:", 
                    @("&Automatic (Based on resolution and orientation)", "&Manual (Specify your own RF value)"), 0)
					
# Variable to hold the RF value
$rf = 0

# Check user choice for RF value
if ($userChoiceRF -eq 0) { # Automatic
    # Automatic RF value logic (will be set in the loop for each file)
    $rf = "Automatic"
} else { # Manual
    # Prompt user for manual RF value
    $rf = Read-Host "Enter your preferred RF value (Numeric values only)"
    # Validate and convert to integer
    if (-not [int]::TryParse($rf, [ref]$null)) {
        Write-Host "Invalid RF value. Please enter a numeric value."
        exit
    }
}

# Clear the terminal after initial configuration
Clear-Host

# Display script title and version
Write-Host "AV1-inizer v$($version) by cryptofyre" -ForegroundColor Cyan

# Loop through each video file and convert it
foreach ($file in $videoFiles) {
    $fileCounter++
    $originalFileSize = (Get-Item $file.FullName).Length
    $destFile = "${destDir}\$($file.BaseName)_AV1.mkv"
	$skipFile = $false
	
	# Get video resolution
    $videoInfo = ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$($file.FullName)"
    $resolution = $videoInfo.Split("x")
    $width = [int]$resolution[0]
    $height = [int]$resolution[1]
	$isPortrait = $height -gt $width
	
	
	# Automatically determine RF level based on clip resolution.
	if ($rf -eq "Automatic") {
		# Default out of range RF
		$rf = 30
	
		# Determine RF setting based on resolution and orientation
		if ($isPortrait) {
			if ($width -le 852 -and $height -le 480) { # 480p Portrait
				$rf = 24
			} elseif ($width -le 1280 -and $height -le 720) { # 720p Portrait
				$rf = 27
			} elseif ($width -le 1920 -and $height -le 1080) { # 1080p Portrait
				$rf = 27
			} elseif ($width -le 2160 -and $height -le 3840) { # 4K Portrait
				$rf = 29
			}
		} else {
			if ($width -le 852 -and $height -le 480) { # 480p
				$rf = 19
			} elseif ($width -le 1280 -and $height -le 720) { # 720p
				$rf = 20
			} elseif ($width -le 1920 -and $height -le 1080) { # 1080p
				$rf = 23
			} elseif ($width -le 3840 -and $height -le 2160) { # 4K
				$rf = 25
			}
		}
    }
	
	# Update the progress bar with current job information
    $progressMessage = "Encoding file ($fileCounter of $totalFiles): $($file.Name) using encoding level $($rf)"
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
        ffmpeg -i "$($file.FullName)" -c:v $encoder -crf $rf -b:v 0 -c:a copy -c:s copy "$destFile" 2>$null

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
	
    # Compare file sizes.
    if (Test-Path $destFile) {
        $convertedFileSize = (Get-Item $destFile).Length
        if ($convertedFileSize -gt $originalFileSize) {
            Write-Host "Warning: $($file.Name) did not benefit from AV1 encoding." -ForegroundColor Yellow
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
