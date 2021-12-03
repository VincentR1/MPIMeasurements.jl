export SequenceControllerParams, SequenceController, getSequenceControllers,
       getSequenceController, setupSequence, startSequence, cancel, trigger

Base.@kwdef struct SequenceControllerParams <: DeviceParams
  "Time after which the data should be saved to an mmapped temp file."
  saveInterval::typeof(1.0u"s") = 2.0u"s"
  "Number of times the control loop tries to control the field."
  maxControlSteps::Integer = 2
end

SequenceControllerParams(dict::Dict) = params_from_dict(SequenceControllerParams, dict)

Base.@kwdef mutable struct SequenceController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::SequenceControllerParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  sequence::Union{Sequence, Nothing} = nothing

  startTime::Union{DateTime, Nothing} = nothing
  task::Union{Task, Nothing} = nothing
  trigger::Channel{Tuple{Int64, Bool}} = Channel{Tuple{Int64, Bool}}(8)
  triggerCount::Threads.Atomic{Int64} = Threads.Atomic{Int64}(0)
  cancelled::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
  readyForTrigger::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
  buffer::Vector{Array{typeof(1.0u"V"), 4}} = []
  isBackgroundTrigger::Vector{Bool} = []
end

function getSequenceControllers(scanner::MPIScanner)
  sequenceControllers = getDevices(scanner, SequenceController)
  if length(sequenceControllers) > 1
    throw(ScannerConfigurationError("The scanner has more than one sequence controller device. This should never happen."))
  else
    return sequenceControllers
  end
end
function getSequenceController(scanner::MPIScanner)
  sequenceControllers =  getSequenceControllers(scanner)
  if length(sequenceControllers) == 0
    throw(ScannerConfigurationError("The scanner has no sequence controller device but one was requested. "*
                                    "Check your scanner configuration as well as your protocol."))
  else
    return sequenceControllers[1]
  end
end

function init(seqCont::SequenceController)
  @debug "Initializing sequence controller with ID `$(seqCont.deviceID)`."

  seqCont.present = true
end

neededDependencies(::SequenceController) = []
optionalDependencies(::SequenceController) = []

Base.close(seqCont::SequenceController) = nothing

function setupControlLoop(seqCont::SequenceController, sequence::Sequence)

end

function setupSequence(seqCont::SequenceController, sequence::Sequence)
  seqCont.sequence = sequence
  daq = dependency(seqCont, AbstractDAQ) # This doesn't work for multiple DAQs yet, since this case is not really a priority
  
  setupControlLoop(seqCont, sequence)
  setup(daq, seqCont.sequence)

  # TODO: Setup mechanical channels
end

function startSequence(seqCont::SequenceController)
  if isnothing(seqCont.task) && !seqCont.cancelled[]
    # Spawn acquisition thread
    if Threads.nthreads() == 1
      @warn "You are currently just using one thread. This could be troublesome in some cases "*
            "(e.g. with an acquisition running while also having a temperature controller running)"
    end

    # Use surveillance unit if available
    if hasDependency(seqCont, SurveillanceUnit)
      su = dependency(seqCont, SurveillanceUnit)
      enableACPower(su)
    else
      @warn "The sequence controller does not have access to a surveillance unit. "*
            "Please check closely if this should be the case."
    end

    daq = dependency(seqCont, AbstractDAQ)

    if needsControlOrDecoupling(seqCont.sequence)
      startTxAndControl(seqCont)
    else
      @info "Nothing to control and thus directly starting transmit part of the sequence"
      startTx(daq)
    end

    @info "Starting acquisition thread."
    seqCont.task = Threads.@spawn acquisitionThread(seqCont)
  else
    @info "The sequence is already running"
  end
end

function cancel(seqCont::SequenceController)
  if isnothing(seqCont.task) || !istaskstarted(seqCont.task)
    @info "The sequence is not running and can therefore not be cancelled."
  else
    Threads.atomic_xchg!(seqCont.cancelled, true)
    finish(seqCont) # Has to be called in order to stop the thread from waiting for triggers
  end
end

function trigger(seqCont::SequenceController, isBackground::Bool=false)
  Threads.atomic_add!(seqCont.triggerCount, 1)
  put!(seqCont.trigger, (seqCont.triggerCount[], isBackground))
  push!(seqCont.isBackgroundTrigger, isBackground)
end

function finish(seqCont::SequenceController)
  put!(seqCont.trigger, (-1, false)) # Signals the acquisition thread to get out of the loop
end

function wait(seqCont::SequenceController)
  Base.wait(seqCont.task)
end

function waitTriggerReady(seqCont::SequenceController)
  while !seqCont.readyForTrigger[]
    sleep(0.1)
  end
end

function acquisitionThread(seqCont::SequenceController)
  daq = dependency(seqCont, AbstractDAQ)

  seqCont.startTime = now()
  @info "The acquisition thread (id $(Threads.threadid())) just started (start time is $(seqCont.startTime))."

  seqScratchDirectory = @get_scratch!(seqCont.sequence.name)
  @info "The scratch directory for intermediate data is `$seqScratchDirectory`."
  #TODO: Detect leftovers and recover from a failed state

  # Create directory for the intermediate trigger files
  triggerSavePath = joinpath(seqScratchDirectory, Dates.format(seqCont.startTime, "yyyy-mm-dd_HH-MM-SS"))
  mkpath(triggerSavePath)

  numSamplingPoints_ = rxNumSamplingPoints(seqCont.sequence)
  numPeriodsPerFrame = acqNumPeriodsPerFrame(seqCont.sequence)

  while !seqCont.cancelled[]
    # Signal the readiness to receive trigger
    Threads.atomic_xchg!(seqCont.readyForTrigger, true)
    currTriggerCount, isBackground = take!(seqCont.trigger)
    Threads.atomic_xchg!(seqCont.readyForTrigger, false)

    if currTriggerCount == -1
      @debug "The acquisition thread received the signal to finish acquisition and will now return."
      break
    end

    @debug "Received an acquisition trigger. The current trigger count is $currTriggerCount."

    if seqCont.cancelled[]
      @debug "The acquisition thread was cancelled while waiting for a trigger."
      break
    end

    numFrames = -1
    try
      numFrames = acqNumFrames(seqCont.sequence, currTriggerCount, isBackground)
    catch e
      if e isa BoundsError
        @error "The specified amount of possible triggers is $(numTriggers(sequence, isBackground))"*
               ", but an additional trigger has been applied. The acquisition will stop now."
        break
      else
        rethrow()
      end
    end

    triggerFilename = joinpath(triggerSavePath, "trigger_$(currTriggerCount).bin")
    numRxChannels_ = numRxChannelsMeasurement(daq)
    bufferShape = (numSamplingPoints_, numRxChannels_, numPeriodsPerFrame, numFrames)
    triggerBuffer = Mmap.mmap(triggerFilename, Array{typeof(1.0u"V"), 4}, bufferShape)

    numFrameAverages = acqNumFrameAverages(seqCont.sequence, isBackground)
    chunkTime = seqCont.params.saveInterval
    framePeriod = numFrameAverages*numPeriodsPerFrame*dfCycle(seqCont.sequence)
    chunk = min(numFrames, max(1, round(Int, ustrip(chunkTime/framePeriod))))

    #TODO: How to deal with the slow DAC?
    # currFr = enableSlowDAC(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
    #                          daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

    @info "Starting acquisition for $numFrames frames with an averaging factor of $numFrameAverages."
    startFrame = MPIMeasurements.currentFrame(daq)
    fr = 1
    while fr <= numFrames
      to = min(fr+chunk-1, numFrames)

      #if tempSensor != nothing
      #  for c = 1:numChannels(tempSensor)
      #      measState.temperatures[c,fr] = getTemperature(tempSensor, c)
      #  end
      #end
      currFrame = startFrame+(fr-1)*numFrameAverages
      numFramesForChunk = numFrameAverages*(length(fr:to))
      @debug "Measuring frame $fr to $to."
      @debug "It should take $(numFramesForChunk*framePeriod |> u"s")."
      @debug startFrame fr to currFrame numFramesForChunk

      @time uMeas, uRef = readData(daq, currFrame, numFramesForChunk, acqNumAverages(seqCont.sequence))
      s = size(uMeas)
      @debug "The size of the measured data is $s."
      if numFrameAverages == 1
        triggerBuffer[:,:,:,fr:to] = uMeas
      else
        tmp = reshape(uMeas, (s[1], s[2], s[3], numFrameAverages, :))
        triggerBuffer[:,:,:,fr:to] = dropdims(mean(tmp, dims=4), dims=4)
      end
      fr = to+1
      
      # Write the current chunk to our temp file
      Mmap.sync!(triggerBuffer)
      break # TODO: Debugging
    end

    push!(seqCont.buffer, triggerBuffer)
  end
  
  #sleep(daq.params.ffRampUpTime)
  @info "Stop sending and disable AC power (if applicable)."
  stopTx(daq)
  if hasDependency(seqCont, SurveillanceUnit)
    disableACPower(su, scanner)
  end
  disconnect(daq)

  # if length(measState.temperatures) > 0
  #   params["calibTemperatures"] = measState.temperatures
  # end
end

function fillMDF(seqCont::SequenceController, mdf::MDFv2InMemory)
  # /measurement/ subgroup
  numFrames = sum([size(triggerBuffer, 4) for triggerBuffer in seqCont.buffer])
  numPeriodsPerFrame_ = acqNumPeriodsPerFrame(seqCont.sequence)
  numRxChannels_ = rxNumChannels(seqCont.sequence)
  numSamplingPoints_ = rxNumSamplingPoints(seqCont.sequence)

  seqScratchDirectory = @get_scratch!(seqCont.sequence.name)
  triggerSavePath = joinpath(seqScratchDirectory, Dates.format(seqCont.startTime, "yyyy-mm-dd_HH-MM-SS"))
  fullDataFilename = joinpath(triggerSavePath, "fullProtocol.bin")
  dataShape = (numSamplingPoints_, numRxChannels_, numPeriodsPerFrame_, numFrames)
  data = Mmap.mmap(fullDataFilename, Array{typeof(1.0u"V"), 4}, dataShape)

  # Sort the frames such that background frames are at the end
  # TODO: Do we only need this if a sparsity transformation is applied?
  # bgPermutation = sortperm(seqCont.isBackgroundTrigger)
  # seqCont.buffer[bgPermutation] = seqCont.buffer
  # seqCont.isBackgroundTrigger[bgPermutation] = seqCont.isBackgroundTrigger

  isBackgroundFrame = Vector{Bool}()
  currentFrame = 1
  for (idx, triggerBuffer) in enumerate(seqCont.buffer)
    data[:, :, :, currentFrame:(currentFrame+size(triggerBuffer, 4))-1] = triggerBuffer
    currentFrame += size(triggerBuffer, 4)
    append!(isBackgroundFrame, fill(seqCont.isBackgroundTrigger[idx], size(triggerBuffer, 4)))
  end

  measData(mdf, ustrip.(u"V", data))
  measIsBackgroundCorrected(mdf, false)
  measIsBackgroundFrame(mdf, isBackgroundFrame)
  measIsFastFrameAxis(mdf, false)
  measIsFourierTransformed(mdf, false)
  measIsFramePermutation(mdf, false)
  measIsFrequencySelection(mdf, false)
  measIsSparsityTransformed(mdf, false)
  measIsSpectralLeakageCorrected(mdf, false)
  measIsTransferFunctionCorrected(mdf, false)

  # /acquisition/ subgroup
  acqGradient(mdf, acqGradient(seqCont.sequence))
  acqNumAverages(mdf, acqNumAverages(seqCont.sequence))
  acqNumFrames(mdf, numFrames) # TODO: Calculate from data (triggered acquisition)
  acqNumPeriodsPerFrame(mdf, numPeriodsPerFrame_)
  acqOffsetField(mdf, acqOffsetField(seqCont.sequence))
  acqStartTime(mdf, seqCont.startTime)

  # /acquisition/drivefield/ subgroup
  dfBaseFrequency(mdf, ustrip(u"Hz", dfBaseFrequency(seqCont.sequence)))
  dfCycle(mdf, ustrip(u"s", dfCycle(seqCont.sequence)))
  dfDivider(mdf, dfDivider(seqCont.sequence))
  dfNumChannels(mdf, dfNumChannels(seqCont.sequence))
  dfPhase(mdf, ustrip.(u"rad", dfPhase(seqCont.sequence)))
  dfStrength(mdf, ustrip.(u"T", dfStrength(seqCont.sequence)))
  dfWaveform(mdf, fromWaveform.(dfWaveform(seqCont.sequence)))

  # /acquisition/receiver/ subgroup
  rxBandwidth(mdf, ustrip(u"Hz", rxBandwidth(seqCont.sequence)))
  #dataConversionFactor TODO: Should we include it or convert the samples directly
  #inductionFactor TODO: should be added from datastore!?
  rxNumChannels(mdf, numRxChannels_)
  rxNumSamplingPoints(mdf, numSamplingPoints_)
  #transferFunction TODO: should be added from datastore!?
  rxUnit(mdf, "V")
end