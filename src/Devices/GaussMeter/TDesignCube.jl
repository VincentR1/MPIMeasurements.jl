export TDesignCubeParams, TDesignCube, setSampleSize, getSampleSize, getT, getN, getRadius, getPositions, getTemperature, resetCube, storeMeasurment

Base.@kwdef struct TDesignCubeParams <: DeviceParams
    T::Int64
    N::Int64
    radius::typeof(1.0u"mm") = 0.0u"mm"
    sampleSize::Int64 = 100
end
TDesignCubeParams(dict::Dict) = params_from_dict(TDesignCubeParams, dict)


Base.@kwdef mutable struct TDesignCube <: Device
    @add_device_fields TDesignCubeParams
    sensors::Union{Vector{GaussMeter},Nothing} = nothing
    sampleSize::Int64 = 100
end

neededDependencies(::TDesignCube) = [GaussMeter]
optionalDependencies(::TDesignCube) = []

function _init(cube::TDesignCube)
    sampleSize = cube.params.sampleSize
    sensors = dependencies(cube, GaussMeter)
    if length(sensors) != cube.params.N
        close.(sensors) # TODO @NH Should not close devices here
        throw("missing Sensors")
    end
    sort!(sensors, by=x -> getPositionID(x))
    cube.sensors = sensors
    setSampleSize(cube, sampleSize)
end

export setSampleSize
function setSampleSize(cube::TDesignCube, sampleSize::Int)
    calledSensors = []
    for sensor in cube.sensors
        try
            setSampleSize.(cube.sensors, sampleSize)
            append!(calledSensors, [sensor])
        catch
            (e)
            setSampleSize.(cube.sensors, cube.sampleSize)
            Throw("Connection to sensor failed:$(getPositionID(s)),Sensor Error: $(e)")
        end
    end
    cube.sampleSize = sampleSize
    return cube.sampleSize
end

export getSampleSize
getSampleSize(cube::TDesignCube) = cube.sampleSize

function getXYZValues(cube::TDesignCube)
    measurement = zeros(3, cube.params.N) .* 1.0u"mT"
    #triggerMeasurment
    triggerMeasurment.(cube.sensors)
    #readmeasurement
    calledSensors = []
    for (i, sensor) in enumerate(cube.sensors)
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

getT(cube::TDesignCube) = cube.params.T
getN(cube::TDesignCube) = cube.params.N
getRadius(cube::TDesignCube) = cube.params.radius

getTemperatures(cube::TDesignCube) = getTemperature.(cube.sensors)

#starts measument and stores it into a hdf5 file
function storeMeasurment(cube::TDesignCube, filename::AbstractString, center_position=[0.0, 0.0, 0.0])

    data = getXYZValues(cube)
    field = ustrip.(u"T", data)
    radius = getRadius(cube)
    N = getN(cube)
    t = getT(cube)
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

resetCube(cube::TDesignCube) = reset.(cube.sensors)
function close(cube::TDesignCube)
    #NOP
end