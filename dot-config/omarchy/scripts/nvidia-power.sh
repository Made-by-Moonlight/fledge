#!/bin/bash
# NVIDIA power management for RTX 3080 stability — only while it drives the
# monitors; as a headless compute card it should be left to idle down.
[[ "$(~/.local/share/fledge/bin/fledge hw display gpu)" == nvidia ]] || exit 0
sleep 5
nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1"  # Prefer maximum performance
echo "NVIDIA power settings applied"
