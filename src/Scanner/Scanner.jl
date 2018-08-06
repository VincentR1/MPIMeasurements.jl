export MPIScanner, getDAQ, getGaussMeter, getRobot, getSafety, getGeneralParams,
      getSurveillanceUnit

type MPIScanner
  params::Dict
  generalParams::Dict
  daq::Union{AbstractDAQ,Void}
  robot::Union{Robot,Void}
  gaussmeter::Union{GaussMeter,Void}
  safty::Union{RobotSetup,Void}
  surveillanceUnit::Union{SurveillanceUnit,Void}
  recoMethod::Function

  function MPIScanner(file::String)
    filename = Pkg.dir("MPIMeasurements","src","Scanner","Configurations",file)
    params = TOML.parsefile(filename)
    generalParams = params["General"]
    return new(params,generalParams,nothing,nothing,nothing,nothing,nothing,()->())
  end
end

getGeneralParams(scanner::MPIScanner) = scanner.generalParams

function getDAQ(scanner::MPIScanner)
  if scanner.daq == nothing && haskey(scanner.params, "DAQ")
    scanner.daq = DAQ(scanner.params["DAQ"])
  end
  return scanner.daq
end

function getRobot(scanner::MPIScanner)
  if scanner.robot == nothing && haskey(scanner.params, "Robot")
    scanner.robot = Robot(scanner.params["Robot"])
  end
  return scanner.robot
end

function getGaussMeter(scanner::MPIScanner)
  if scanner.gaussmeter == nothing && haskey(scanner.params, "GaussMeter")
    scanner.gaussmeter = GaussMeter(scanner.params["GaussMeter"])
  end
  return scanner.gaussmeter
end

function getSafety(scanner::MPIScanner)
  if scanner.safty == nothing && haskey(scanner.params, "Safety")
    scanner.safty = RobotSetup(scanner.params["Safety"])
  end
  return scanner.safty
end

function getSurveillanceUnit(scanner::MPIScanner)
  if scanner.surveillanceUnit == nothing && haskey(scanner.params, "SurveillanceUnit")
    scanner.surveillanceUnit = SurveillanceUnit(scanner.params["SurveillanceUnit"])
  end
  return scanner.surveillanceUnit
end
