export TDesignSensorArrayParams, TDesignSensorArray, setSampleSize, getSampleSize, getT, getN, getRadius, getPositions, getTemperature, resetCube, storeMeasurment

Base.@kwdef struct TDesignSensorArrayParams <: DeviceParams
    T::Int64
    N::Int64
    radius::typeof(1.0u"mm") = 0.0u"mm"
    sampleSize::Int64 = 100
end
TDesignSensorArrayParams(dict::Dict) = params_from_dict(TDesignSensorArray, dict)


Base.@kwdef mutable struct TDesignSensorArray <: Device
    @add_device_fields TDesignSensorArrayParams
    sensors::Union{Vector{GaussMeter},Nothing} = nothing
    sampleSize::Int64 = 100
end

neededDependencies(::TDesignSensorArray) = [GaussMeter]
optionalDependencies(::TDesignSensorArray) = []

function _init(tdsa::TDesignSensorArray)
    sampleSize = tdsa.params.sampleSize
    sensors = dependencies(tdsa, GaussMeter)
    if length(sensors) != tdsa.params.N
        close.(sensors) # TODO @NH Should not close devices here
        throw("missing Sensors")
    end
    sort!(sensors, by=x -> getPositionID(x))
    tdsa.sensors = sensors
    setSampleSize(tdsa, sampleSize)
end

export setSampleSize
function setSampleSize(tdsa::TDesignSensorArray, sampleSize::Int)
    calledSensors = []
    for sensor in tdsa.sensors
        try
            setSampleSize.(tdsa.sensors, sampleSize)
            append!(calledSensors, [sensor])
        catch
            (e)
            setSampleSize.(tdsa.sensors, tdsa.sampleSize)
            Throw("Connection to sensor failed:$(getPositionID(s)),Sensor Error: $(e)")
        end
    end
    tdsa.sampleSize = sampleSize
    return tdsa.sampleSize
end

export getSampleSize
getSampleSize(tdsa::TDesignSensorArray) = tdsa.sampleSize

function getXYZValues(tdsa::TDesignSensorArray)
    measurement = zeros(3, tdsa.params.N) .* 1.0u"mT"
    #triggerMeasurment
    triggerMeasurment.(tdsa.sensors)
    #readmeasurement
    calledSensors = []
    for (i, sensor) in enumerate(tdsa.sensors)
        try
            measurement[:, i] = receiveMeasurment(sensor)
            append!(calledSensors, [sensor])
        catch e
            reset.(calledSensors)
            throw("Problem with sensor: $(i), Error Massage : $(e)")
        end
    end
    return measurement
end

getT(tdsa::TDesignSensorArray) = tdsa.params.T
getN(tdsa::TDesignSensorArray) = tdsa.params.N
getRadius(tdsa::TDesignSensorArray) = tdsa.params.radius

getTemperatures(tdsa::TDesignSensorArray) = getTemperature.(tdsa.sensors)

#starts measument and stores it into a hdf5 file
function storeMeasurment(tdsa::TDesignSensorArray, filename::AbstractString, center_position=[0.0, 0.0, 0.0])

    data = getXYZValues(tdsa)
    field = ustrip.(u"T", data)
    radius = getRadius(tdsa)
    N = getN(tdsa)
    t = getT(tdsa)
    center = center_position
    correction = zeros(Float64, 3, 3)
    h5open(filename, "w") do file
        write(file, "/fields", field)# measured field (size: 3 x #points x #patches)
        write(file, "/positions/tDesign/radius", ustrip(u"m", radius))# radius of the measured ball
        write(file, "/positions/tDesign/N", N)# number of points of the t-design
        write(file, "/positions/tDesign/t", t)# t of the t-design
        write(file, "/positions/tDesign/center", center)# center of the measured ball
        write(file, "/sensor/correctionTranslation", correction)# center of the measured ball


    end
    return data
end

resetCube(tdsa::TDesignSensorArray) = reset.(tdsa.sensors)
function close(tdsa::TDesignSensorArray)
    #NOP
end