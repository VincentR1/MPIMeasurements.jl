export SimulatedGaussMeter, SimulatedGaussMeterParams, getXValue, getYValue, getZValue

Base.@kwdef struct SimulatedGaussMeterParams <: DeviceParams
  coordinateTransformation::Matrix{Float64} = Matrix{Float64}(I,(3,3))
end
SimulatedGaussMeterParams(dict::Dict) = params_from_dict(SimulatedGaussMeterParams, dict)

Base.@kwdef mutable struct SimulatedGaussMeter <: GaussMeter
  @add_device_fields SimulatedGaussMeterParams
end

function _init(gauss::SimulatedGaussMeter)
  # NOP
end

neededDependencies(::SimulatedGaussMeter) = []
optionalDependencies(::SimulatedGaussMeter) = []

Base.close(gauss::SimulatedGaussMeter) = nothing

getXYZValue(gauss::SimulatedGaussMeter) = [1.0u"mT",2.0u"mT",3.0u"mT"]
getTemperature(gauss::SimulatedGaussMeter) = 20.0u"°C"
getFrequency(gauss::SimulatedGaussMeter) = 0.0u"Hz"
calculateFieldError(gauss::SimulatedGaussMeter, magneticField::Vector{<:Unitful.BField}) = 1.0u"mT"