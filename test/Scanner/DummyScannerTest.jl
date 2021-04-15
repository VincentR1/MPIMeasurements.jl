using ReusePatterns

@testset "Dummy scanner" begin
  scannerName_ = "TestDummyScanner"
  scanner = MPIScanner(scannerName_)

  @testset "Meta" begin
    @test getName(scanner) == scannerName_
    @test getConfigDir(scanner) == joinpath(testConfigDir, scannerName_)
    @test getGUIMode(scanner::MPIScanner) == false
  end

  @testset "General" begin
    generalParams = getGeneralParams(scanner)
    @test typeof(generalParams) == MPIScannerGeneral
    @test generalParams.boreSize == 1337u"mm"
    @test generalParams.facility == "My awesome institute"
    @test generalParams.manufacturer == "Me, Myself and I"
    @test generalParams.name == scannerName_
    @test generalParams.topology == "FFL"
    @test generalParams.gradient == 42u"T/m"
    @test scannerBoreSize(scanner) == 1337u"mm"
    @test scannerFacility(scanner) == "My awesome institute"
    @test scannerManufacturer(scanner) == "Me, Myself and I"
    @test scannerName(scanner) == scannerName_
    @test scannerTopology(scanner) == "FFL"
    @test scannerGradient(scanner) == 42u"T/m"
  end

  @testset "Devices" begin

    # TODO: add getDevices tests

    @testset "DAQ" begin
      daq = getDevice(scanner, "my_daq_id")
      @test typeof(daq) == concretetype(DummyDAQ) # This implies implementation details...
      @test daq.params.samplesPerPeriod == 1000
      @test daq.params.sendFrequency == 25u"kHz"
    end

    @testset "GaussMeter" begin
      gauss = getDevice(scanner, "my_gauss_id")
      @test typeof(gauss) == concretetype(DummyGaussMeter) # This implies implementation details...
    end
  end
end