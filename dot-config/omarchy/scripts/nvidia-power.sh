#!/bin/bash
# NVIDIA power management for RTX 3080 stability
sleep 5
nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1"  # Prefer maximum performance
echo "NVIDIA power settings applied"
