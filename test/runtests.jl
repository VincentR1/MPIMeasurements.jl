using MPIMeasurements
using Test
using Unitful

#ENV["JULIA_DEBUG"] = "MPIMeasurements"

# Add test configurations to path
testConfigDir = normpath(string(@__DIR__), "TestConfigs")
addConfigurationPath(testConfigDir)

include("Devices/DeviceTests.jl")
include("Scanner/ScannerTests.jl")